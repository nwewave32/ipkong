import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/climate.dart';
import '../domain/models/enums.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'care_link_teaser.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final settings = ref.watch(settingsRepositoryProvider);
    final winter = ref.watch(winterModeProvider);
    final climate = ref.watch(climateProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.tabSettings)),
      body: ListView(
        children: [
          _SectionLabel(s.settingsNotifications),

          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(s.notifyTime),
            subtitle: Text(s.notifyTimeDesc),
            isThreeLine: true,
            trailing: Text(
              '${settings.notifyHour.toString().padLeft(2, '0')}:'
              '${settings.notifyMinute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: settings.notifyHour,
                  minute: settings.notifyMinute,
                ),
              );
              if (picked == null) return;
              await settings.setNotifyTime(picked.hour, picked.minute);
              await ref.read(plantListProvider.notifier).load();
            },
          ),

          _WinterModeRow(
            enabled: winter,
            climate: climate,
            onChanged: (v) async {
              await settings.setWinterMode(v);
              ref.read(winterModeProvider.notifier).state = v;
              await ref.read(plantListProvider.notifier).onWinterModeChanged();
            },
          ),

          const Divider(height: 32),
          _SectionLabel(s.settingsData),

          ListTile(
            leading: const Icon(Icons.ios_share),
            title: Text(s.exportData),
            subtitle: Text(s.exportDataDesc),
            isThreeLine: true,
            onTap: () => _export(context, ref),
          ),

          ListTile(
            leading: const Icon(Icons.language),
            title: Text(s.language),
            trailing: DropdownButton<String?>(
              value: locale?.languageCode,
              onChanged: (v) async {
                await settings.setLocaleCode(v);
                ref.read(localeProvider.notifier).state =
                    v == null ? null : Locale(v);
              },
              items: [
                DropdownMenuItem(value: null, child: Text(s.languageSystem)),
                const DropdownMenuItem(value: 'ko', child: Text('한국어')),
                const DropdownMenuItem(value: 'en', child: Text('English')),
              ],
            ),
          ),

          const Divider(height: 32),
          _SectionLabel(s.comingSoon),
          const CareLinkTeaser(),

          const SizedBox(height: 28),
          Center(
            child: Text(
              '${s.appName} · ${s.tagline}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 무엇이 나가는지, 왜 백업이 필요한지 먼저 알려주고 내보낸다.
  ///
  /// 두 갈래를 다 둔다. **파일 저장·공유**가 기본이다 — 메일·드라이브·에어드롭
  /// 어디로든 보낼 수 있고, 클립보드처럼 다음 복사에 덮어써지지 않는다.
  /// **복사**는 메모 앱에 바로 붙여넣고 싶은 사람을 위해 남긴다.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final data = await ref.read(plantRepositoryProvider).exportAll();
    final plants = (data['plants'] as List).length;
    final events = (data['watering_events'] as List).length;

    if (!context.mounted) return;

    if (plants == 0) {
      messenger.showSnackBar(SnackBar(content: Text(s.exportNothing)));
      return;
    }

    final choice = await showDialog<_ExportChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.exportDialogTitle),
        content: Text(s.exportDialogBody(plants, events)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ExportChoice.copy),
            child: Text(s.exportCopy),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ExportChoice.share),
            child: Text(s.exportShare),
          ),
        ],
      ),
    );

    if (choice == null || !context.mounted) return;

    final json = const JsonEncoder.withIndent('  ').convert(data);

    switch (choice) {
      case _ExportChoice.copy:
        await Clipboard.setData(ClipboardData(text: json));
        messenger.showSnackBar(SnackBar(content: Text(s.exportDone)));
      case _ExportChoice.share:
        await _shareAsFile(context, messenger, s, json);
    }
  }

  /// 파일로 써서 공유 시트에 넘긴다.
  ///
  /// 넘긴 뒤에는 **반드시 지운다.** 임시 폴더는 OS 가 치울 때까지 남는데,
  /// 그동안 사용자 데이터 전체가 평문으로 기기에 놓여 있게 된다.
  /// `share_plus` 는 안드로이드에서 파일을 자기 캐시로 복사한 뒤 공유하고
  /// (`Share.kt` 의 `copyToShareCacheFolder`), iOS 는 시트가 닫힌 뒤에
  /// `share()` 가 반환되므로, 이 시점의 삭제는 받는 쪽을 깨뜨리지 않는다.
  Future<void> _shareAsFile(
    BuildContext context,
    ScaffoldMessengerState messenger,
    AppStrings s,
    String json,
  ) async {
    // iPad 는 공유 시트를 띄울 앵커 사각형을 요구한다. 없으면 예외가 난다.
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    File? file;
    try {
      file = await _writeBackupFile(json);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: s.exportFileSubject,
          sharePositionOrigin: origin,
        ),
      );
      if (result.status == ShareResultStatus.success) {
        messenger.showSnackBar(SnackBar(content: Text(s.exportSaved)));
      }
    } catch (e, st) {
      // 공유 시트가 없는 환경(일부 데스크톱·에뮬레이터)에서도 데이터를
      // 꺼낼 방법은 남겨둔다. 백업 기능이 통째로 실패하면 안 된다.
      // 다만 조용히 삼키지는 않는다 — 진짜 버그가 "저장 실패"로 둔갑한다.
      debugPrint('[ipkong] 백업 파일 공유 실패, 클립보드로 대체: $e\n$st');
      await Clipboard.setData(ClipboardData(text: json));
      messenger.showSnackBar(SnackBar(content: Text(s.exportFellBackToCopy)));
    } finally {
      await _deleteQuietly(file);
    }
  }

  /// 임시 폴더에 날짜가 박힌 이름으로 쓴다. 공유 시트가 파일 이름을 그대로
  /// 보여주므로, 받는 쪽에서 언제 받은 백업인지 알 수 있어야 한다.
  Future<File> _writeBackupFile(String json) async {
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/ipkong-backup-$stamp.json');
    return file.writeAsString(json);
  }

  /// 정리 단계의 실패로 공유 결과를 뒤집지는 않는다. 이미 끝난 일이다.
  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('[ipkong] 백업 임시 파일 삭제 실패: $e');
    }
  }
}

enum _ExportChoice { copy, share }

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 겨울 모드 행.
///
/// 토글만 두면 사용자는 이게 무엇을 하는지도, 지금 실제로 적용되고 있는지도
/// 알 수 없다. 설명 한 줄과 **현재 상태 배지**를 함께 보여준다.
///
/// ListTile 계열은 높이 제약이 있어 세 줄 이상을 넣으면 넘치므로 직접 조립한다.
class _WinterModeRow extends StatelessWidget {
  const _WinterModeRow({
    required this.enabled,
    required this.climate,
    required this.onChanged,
  });

  final bool enabled;
  final Climate climate;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isWinterNow = ClimateResolver.isWinter(DateTime.now(), climate);

    // 열대에는 겨울이 없다. 토글을 켜도 아무 일이 일어나지 않으므로
    // 그 사실을 숨기지 않고 그대로 알려준다.
    final String status;
    final bool active;
    if (climate == Climate.tropical) {
      status = s.winterStatusTropical;
      active = false;
    } else if (!isWinterNow) {
      status = s.winterStatusNotWinter;
      active = false;
    } else if (enabled) {
      status = s.winterStatusActive;
      active = true;
    } else {
      status = s.winterStatusOffInWinter;
      active = false;
    }

    return InkWell(
      onTap: () => onChanged(!enabled),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.ac_unit, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.winterMode,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      Switch(value: enabled, onChanged: onChanged),
                    ],
                  ),
                  Text(
                    s.winterModeDesc,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _StatusBadge(label: status, active: active),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              active ? Icons.check_circle : Icons.info_outline,
              size: 15,
              color: fg,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
