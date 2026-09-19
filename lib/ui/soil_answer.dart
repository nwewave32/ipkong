import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/enums.dart';
import '../domain/models/plant.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// 흙 상태 응답 버튼 한 줄.
///
/// '오늘' 카드와 알림 탭 시트가 **같은 위젯**을 쓴다. 사용자는 잠금화면에서
/// 길게 눌러 답하든, 알림을 탭해 답하든, 앱을 열어 답하든 같은 선택지를
/// 기대한다. 세 곳에 따로 적어두면 버튼 하나를 고칠 때 한 곳만 고쳐져
/// 조용히 어긋난다 — 알림 버튼 문구는 `NotificationCopy.actions` 가 같은
/// 순서로 들고 있으므로 그쪽을 고칠 때 여기도 함께 본다.
class SoilAnswerButtons extends StatelessWidget {
  const SoilAnswerButtons({
    required this.isSettled,
    required this.onRespond,
    required this.onWater,
    super.key,
  });

  /// 정착 전에는 흙 상태 3택, 정착 후에는 단순 2택.
  final bool isSettled;

  final ValueChanged<SoilResponse> onRespond;
  final VoidCallback onWater;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: isSettled
          ? [
              FilledButton(onPressed: onWater, child: Text(s.watered)),
              OutlinedButton(
                onPressed: () => onRespond(SoilResponse.tooWet),
                child: Text(s.stillMoist),
              ),
            ]
          : [
              OutlinedButton(
                onPressed: () => onRespond(SoilResponse.tooWet),
                child: Text(s.tooWet),
              ),
              FilledButton(
                onPressed: () => onRespond(SoilResponse.justRight),
                child: Text(s.justRight),
              ),
              OutlinedButton(
                onPressed: () => onRespond(SoilResponse.tooDry),
                child: Text(s.tooDry),
              ),
            ],
    );
  }
}

/// 알림 본문을 탭해서 들어온 사람에게 그 식물의 답변 버튼을 바로 내민다.
///
/// iOS 는 알림을 길게 누르기 전에는 액션 버튼을 보여주지 않고, 그 동작을 바꾸는
/// API 가 없다. 길게 누를 줄 모르는 사람에게는 **본문 탭이 유일한 경로**이므로,
/// 앱을 열어주는 데서 멈추지 않고 여기까지 데려다준다.
///
/// 답을 누르면 시트부터 닫는다. 반영은 DB 를 거치므로 한 박자 걸리는데, 그
/// 동안 버튼이 남아 있으면 안 눌린 줄 알고 한 번 더 누른다.
Future<void> showSoilAnswerSheet(
  BuildContext context,
  WidgetRef ref,
  Plant plant,
) {
  final notifier = ref.read(plantListProvider.notifier);

  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SoilAnswerSheet(
      plant: plant,
      onRespond: (response) {
        Navigator.of(sheet).pop();
        notifier.respond(plant.id, response);
      },
      onWater: () {
        Navigator.of(sheet).pop();
        notifier.waterNow(plant.id);
      },
    ),
  );
}

/// 시트의 내용물. 프로바이더를 모르는 순수 위젯이라 DB 없이 테스트된다.
class SoilAnswerSheet extends StatelessWidget {
  const SoilAnswerSheet({
    required this.plant,
    required this.onRespond,
    required this.onWater,
    super.key,
  });

  final Plant plant;
  final ValueChanged<SoilResponse> onRespond;
  final VoidCallback onWater;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plant.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              plant.isSettled ? s.settledQuestion : s.soilQuestion,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            SoilAnswerButtons(
              isSettled: plant.isSettled,
              onRespond: onRespond,
              onWater: onWater,
            ),
          ],
        ),
      ),
    );
  }
}
