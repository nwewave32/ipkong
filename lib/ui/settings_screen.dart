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
import 'notify_time_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final settings = ref.watch(settingsRepositoryProvider);
    final notifyAt = ref.watch(notifyTimeProvider);
    final winter = ref.watch(winterModeProvider);
    final climate = ref.watch(climateProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.tabSettings)),
      body: ListView(
        children: [
          _SectionLabel(s.settingsNotifications),

          _NotifyTimeRow(
            value: notifyAt,
            onChanged: (t) async {
              // 겨울 모드와 같은 순서다 — 저장소에 쓰고, 화면이 보는 상태를
              // 갱신하고, 재예약을 돌린다. 가운데를 빠뜨리면 저장은 되는데
              // 화면이 옛 값을 계속 보여준다.
              await settings.setNotifyTime(t.hour, t.minute);
              ref.read(notifyTimeProvider.notifier).state = t;
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

          _SettingsRow(
            icon: Icons.ios_share,
            title: s.exportData,
            description: s.exportDataDesc,
            alignment: CrossAxisAlignment.center,
            onTap: () => _export(context, ref),
          ),

          _SettingsRow(
            icon: Icons.language,
            title: s.language,
            alignment: CrossAxisAlignment.center,
            trailing: DropdownButton<String?>(
              value: locale?.languageCode,
              onChanged: (v) async {
                await settings.setLocaleCode(v);
                ref.read(localeProvider.notifier).state = v == null
                    ? null
                    : Locale(v);
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
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

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
    final stamp =
        '${now.year}'
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

/// 설정 행이 공유하는 치수.
///
/// 행마다 여백을 따로 적으면 `top: 2`, `12 / 14` 같은 눈대중 보정이 쌓이고,
/// 글꼴이나 컨트롤 높이가 바뀌는 순간 전부 어긋난다. 한곳에서 정한다.
abstract final class _SettingsLayout {
  /// 좌우 여백. 섹션 라벨·카드 바깥 여백도 이 값에 맞춘다.
  static const horizontal = 16.0;

  /// 위아래 여백. 위와 아래가 달라지면 가운데 정렬이 그만큼 한쪽으로 쏠린다.
  static const vertical = 12.0;

  /// 아이콘과 글 사이, 글과 오른쪽 컨트롤 사이.
  static const leadingGap = 16.0;
  static const trailingGap = 12.0;

  /// 한 줄짜리 행도 이 높이는 가진다 (Material 목록 한 줄 기준).
  static const minHeight = 56.0;

  /// 제목 줄과 설명 사이. 제목 줄에 컨트롤이 있으면 그 아랫선에 설명이 바로
  /// 붙어 보이므로 숨 쉴 틈을 둔다.
  static const titleGap = 4.0;

  /// 설명 아래 부가 요소(상태 배지 등)와의 간격.
  static const footerGap = 8.0;
}

/// 설정 화면의 한 행 — 아이콘 · 제목 · 오른쪽 컨트롤, 그 아래 설명.
///
/// 세로 정렬은 **제목 줄 안에서** 잡고, 어떻게 잡을지는 밖에서 넘겨받는다
/// ([alignment], 기본은 가운데). 예전에는 각 행이 `start` 정렬에 아이콘을
/// `top: 2` 만큼 내려 맞췄는데, 오른쪽 컨트롤 높이(스위치 48, 알약 32)에 따라
/// 제목 줄의 중심이 달라져서 아이콘이 행마다 6~10px 씩 위로 떠 있었다.
///
/// 설명까지 묶어서 가운데를 잡으면 컨트롤이 설명 옆으로 끼어들어 설명 폭이
/// 좁아지고, 한글이 단어 중간에서 끊긴다. 그래서 설명과 [footer] 는 제목 줄
/// 아래에서 글 시작선부터 오른쪽 끝까지 쓴다.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.description,
    this.trailing,
    this.footer,
    this.onTap,
    this.alignment = CrossAxisAlignment.center,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;

  /// 제목 줄 안에서 아이콘 · 제목 · 오른쪽 컨트롤의 세로 정렬.
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 설명과 부가 요소는 글 시작선(아이콘 폭 + 간격)에서 시작해 오른쪽 끝까지
    // 쓴다. 컨트롤 옆에 끼워 넣으면 폭이 좁아져 한글이 단어 중간에서 끊긴다.
    const textIndent = 24 + _SettingsLayout.leadingGap;

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _SettingsLayout.horizontal,
        vertical: _SettingsLayout.vertical,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 제목 줄: 아이콘 · 제목 · 컨트롤이 이 줄 안에서 [alignment] 로 선다.
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: description == null
                  ? _SettingsLayout.minHeight - _SettingsLayout.vertical * 2
                  : 0,
            ),
            child: Row(
              crossAxisAlignment: alignment,
              children: [
                Icon(icon, color: scheme.onSurfaceVariant),
                const SizedBox(width: _SettingsLayout.leadingGap),
                Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
                if (trailing != null) ...[
                  const SizedBox(width: _SettingsLayout.trailingGap),
                  trailing!,
                ],
              ],
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(
                left: textIndent,
                top: _SettingsLayout.titleGap,
              ),
              child: Text(
                description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(
                left: textIndent,
                top: _SettingsLayout.footerGap,
              ),
              child: footer,
            ),
        ],
      ),
    );

    if (onTap == null) return row;
    // 행 전체가 버튼일 때는 제목·설명·스위치 상태를 한 번에 읽힌다
    // (ListTile 이 해주던 일).
    return MergeSemantics(child: InkWell(onTap: onTap, child: row));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _SettingsLayout.horizontal,
        16,
        _SettingsLayout.horizontal,
        4,
      ),
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

    return _SettingsRow(
      icon: Icons.ac_unit,
      title: s.winterMode,
      description: s.winterModeDesc,
      trailing: Switch(value: enabled, onChanged: onChanged),
      footer: _StatusBadge(label: status, active: active),
      alignment: CrossAxisAlignment.center,
      onTap: () => onChanged(!enabled),
    );
  }
}

/// 알림 시간 행.
///
/// 이 앱에서 사용자가 실제로 만지는 유일한 알림 설정이라, 목록의 한 줄로
/// 흘려보내지 않고 [_WinterModeRow] 와 같은 구조로 세운다 — 아이콘 + 제목 +
/// 설명, 그리고 지금 값이 한눈에 보이는 자리.
///
/// 고르는 일은 전부 바텀시트가 맡는다 ([showNotifyTimeSheet]). 여기는 지금
/// 값을 보여주고 그 시트로 들어가는 문만 둔다 — 같은 선택지를 두 곳에 두면
/// 어느 쪽이 진짜인지 헷갈린다.
class _NotifyTimeRow extends StatelessWidget {
  const _NotifyTimeRow({required this.value, required this.onChanged});

  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  String _format(BuildContext context, TimeOfDay t) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        t,
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  Future<void> _pick(BuildContext context) async {
    final picked = await showNotifyTimeSheet(context, initial: value);
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return _SettingsRow(
      icon: Icons.notifications_outlined,
      title: s.notifyTime,
      description: s.notifyTimeDesc,
      alignment: CrossAxisAlignment.center,
      trailing: _TimePill(
        label: _format(context, value),
        // 알약은 시각만 읽힌다. 무엇을 바꾸는 버튼인지까지 읽어주지 않으면
        // 화면을 못 보는 사람에게는 그냥 "오전 9:00" 이라는 버튼이 하나 있는
        // 것일 뿐이다.
        semanticLabel:
            '${s.notifyTime}, '
            '${_format(context, value)}, ${s.notifyTimeChange}',
        onTap: () => _pick(context),
      ),
      // 행 전체를 버튼으로 두지 않는다. 알약이 이미 버튼이고, 둘을 겹치면
      // 스크린 리더가 같은 동작을 두 번 읽는다.
    );
  }
}

/// 지금 설정된 시각. 누르면 시간 선택기가 열린다.
///
/// 설정값을 회색 글씨로 두면 누를 수 있다는 걸 알 수 없다. 그렇다고 색을 채운
/// 알약으로 두면 한 화면에서 그것만 튀어 부담스럽다. 배경 없이 **프라이머리
/// 색 글자와 작은 연필**로 "여기가 버튼"이라고 말하고, 누르는 순간에만 물결이
/// 보인다.
class _TimePill extends StatelessWidget {
  const _TimePill({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;

  /// 스크린 리더가 읽을 문구. 눈으로 보는 [label] 은 시각만 담지만, 읽어주는
  /// 쪽에는 이게 무엇의 시각이고 누르면 무슨 일이 일어나는지까지 있어야 한다.
  final String semanticLabel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // ExcludeSemantics 는 InkWell **안쪽**에 둔다. 바깥에 두면 InkWell 의 탭
    // 액션까지 지워져서, 스크린 리더에는 버튼이라고 읽히는데 두 번 탭해도
    // 아무 일도 일어나지 않는다. 안쪽에 두면 시각 문구가 중복으로 읽히는 것만
    // 막고 탭은 살아남는다.
    return Semantics(
      // container 를 켜지 않으면 이 주석이 노드를 새로 만들지 않고 주변
      // 텍스트와 **한 덩어리로 합쳐진다.** 그러면 제목·설명·"자주 쓰는 시간"
      // 까지 묶인 거대한 버튼 하나가 읽히고, 정작 각 문구는 따로 훑을 수 없다.
      container: true,
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ExcludeSemantics(
          child: Padding(
            // 위아래를 줄여 제목 줄이 설명 쪽으로 불룩 튀어나오지 않게 한다.
            // 좌우는 손가락이 닿을 폭을 남긴다.
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    // 시각이 바뀌어도 폭이 들썩이지 않게 고정폭 숫자를 쓴다.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 16, color: scheme.primary),
              ],
            ),
          ),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.info_outline,
            size: 15,
            color: fg,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
