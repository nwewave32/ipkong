import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/climate.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// 겨울 확인 카드.
///
/// 타임존 테이블은 완벽할 수 없다. 인도 북부와 남부가 다르고, 브라질
/// 마나우스와 포르투알레그리가 다르고, 난방을 세게 트는 집은 겨울에도
/// 흙이 빨리 마른다. 그래서 **타임존은 "언제 물어볼지"를 정하는 데만 쓰고,
/// 실제 적용은 사용자 응답으로 결정한다.**
///
/// 탭 한 번으로 남반구·열대·난방 변수가 한꺼번에 해결되고,
/// 이 패턴은 앱의 브랜드(마음대로 정하지 않고 확인한다)와도 일치한다.
Future<void> maybeShowWinterPrompt(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsRepositoryProvider);
  final climate = ref.read(climateProvider);
  final now = DateTime.now();

  if (!ClimateResolver.isWinter(now, climate)) return;

  // 같은 겨울에 두 번 묻지 않는다. 남반구는 겨울이 연중에 있으므로
  // 연도만으로 충분하다.
  final seasonKey = '${now.year}-W';
  if (settings.winterAskedSeason == seasonKey) return;
  await settings.setWinterAskedSeason(seasonKey);

  if (!context.mounted) return;
  final s = AppStrings.of(context);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Text('🍂 '),
          Expanded(child: Text(s.winterCardTitle)),
        ],
      ),
      content: Text(s.winterCardBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(s.winterNo),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(s.winterYes),
        ),
      ],
    ),
  );

  if (result == null) return;

  await settings.setWinterMode(result);
  ref.read(winterModeProvider.notifier).state = result;
  // 계절이 바뀌었으니 정착을 풀어 새 주기를 한 번 검증하게 한다.
  await ref.read(plantListProvider.notifier).onWinterModeChanged();
}
