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
/// [now] 는 테스트에서 겨울 날짜를 넣기 위한 것이다. 앱은 넘기지 않는다.
Future<void> maybeShowWinterPrompt(
  BuildContext context,
  WidgetRef ref, {
  DateTime? now,
}) async {
  final settings = ref.read(settingsRepositoryProvider);
  final climate = ref.read(climateProvider);
  final today = now ?? DateTime.now();

  if (!ClimateResolver.isWinter(today, climate)) return;

  // 같은 겨울에 두 번 묻지 않는다. 남반구는 겨울이 연중에 있으므로
  // 연도만으로 충분하다.
  final seasonKey = '${today.year}-W';
  if (settings.winterAskedSeason == seasonKey) return;

  if (!context.mounted) return;
  final s = AppStrings.of(context);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // 기본 여백(좌우 40)은 폰에서 카드를 좁게 만든다. 본문이 두 줄로
      // 끊기면 "물주기를 조금 늦출까요?" 라는 질문이 한눈에 들어오지 않는다.
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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

  // 바깥을 눌러 닫은 경우다. 아직 **답하지 않았으므로** 물어봤다고 적지
  // 않는다 — 다음에 앱을 켜면 다시 묻는다.
  //
  // ⚠️ 이 기록을 다이얼로그보다 먼저 해두면, 질문을 읽지도 않고 닫은
  // 사람에게 그 해 겨울 내내 다시 묻지 않게 된다. 겨울 모드는 설정에서
  // 직접 켤 수 있지만, 그런 설정이 있다는 걸 알려주는 유일한 장치가
  // 이 카드다.
  if (result == null) return;

  await settings.setWinterAskedSeason(seasonKey);
  await settings.setWinterMode(result);
  ref.read(winterModeProvider.notifier).state = result;
  // 계절이 바뀌었으니 정착을 풀어 새 주기를 한 번 검증하게 한다.
  await ref.read(plantListProvider.notifier).onWinterModeChanged();
}
