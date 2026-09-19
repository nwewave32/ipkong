import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/enums.dart';
import '../domain/models/plant.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// 흙 상태 응답 선택지.
///
/// '오늘' 카드와 알림 탭 시트가 **같은 위젯**을 쓴다. 사용자는 잠금화면에서
/// 길게 눌러 답하든, 알림을 탭해 답하든, 앱을 열어 답하든 같은 선택지를
/// 기대한다. 세 곳에 따로 적어두면 버튼 하나를 고칠 때 한 곳만 고쳐져
/// 조용히 어긋난다 — 알림 버튼 문구는 `NotificationCopy.actions` 가 같은
/// 순서로 들고 있으므로 그쪽을 고칠 때 여기도 함께 본다.
///
/// **선택지마다 한 줄 설명이 붙는다.** 라벨만 있으면 '축축'과 '바짝'은
/// 분명한데 가운데인 '적당'을 무엇으로 판단할지 알 수 없다. 겉흙만 보면
/// 적당한 흙과 속까지 마른 흙이 똑같이 보이기 때문이다 — 세 선택지를 가르는
/// 기준(속흙의 상태)을 설명이 대신 말해준다.
///
/// **세 선택지의 무게는 같다.** 가운데를 강조된 버튼으로 두면 무엇을 눌러야
/// 할지 모르는 사람이 그쪽으로 쏠리고, 그 답이 곧 학습 데이터라 주기가
/// 조용히 틀어진다. 관찰을 보고하는 자리이지 권하는 자리가 아니다.
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

    final options = isSettled
        ? [
            // 물을 줬다는 건 관찰이 아니라 행동이고, 정착된 식물에서 기대되는
            // 기본 동작이다. 여기서는 강조해도 판단을 왜곡하지 않는다.
            _Option(
              emoji: '🚿',
              label: s.watered,
              description: s.wateredHint,
              onTap: onWater,
              emphasized: true,
            ),
            _Option(
              emoji: '💧',
              label: s.stillMoist,
              description: s.stillMoistHint,
              onTap: () => onRespond(SoilResponse.tooWet),
            ),
          ]
        : [
            _Option(
              emoji: '💧',
              label: s.tooWet,
              description: s.tooWetHint,
              onTap: () => onRespond(SoilResponse.tooWet),
            ),
            _Option(
              emoji: '👌',
              label: s.justRight,
              description: s.justRightHint,
              onTap: () => onRespond(SoilResponse.justRight),
            ),
            _Option(
              emoji: '🏜️',
              label: s.tooDry,
              description: s.tooDryHint,
              onTap: () => onRespond(SoilResponse.tooDry),
            ),
          ];

    // stretch 로 늘려 가로를 꽉 채운다. 설명 한 줄이 들어가면 버튼이 저마다
    // 다른 너비로 서게 되는데, 그러면 읽는 눈이 왼쪽 끝을 따라가지 못한다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, o) in options.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          o,
        ],
      ],
    );
  }
}

/// 선택지 한 줄. 이모지 + 라벨 + 설명.
class _Option extends StatelessWidget {
  const _Option({
    required this.emoji,
    required this.label,
    required this.description,
    required this.onTap,
    this.emphasized = false,
  });

  final String emoji;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final style = ButtonStyle(
      alignment: Alignment.centerLeft,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final child = Row(
      children: [
        // 이모지는 장식이다. 라벨과 설명이 이미 전부 말해준다.
        ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 22))),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );

    // tonal 은 채워져 있으면서도 글자색이 한 가지라, 라벨과 설명이 같은 색
    // 위에 놓인다. filled 로 두면 설명 줄의 대비를 따로 맞춰야 한다.
    return emphasized
        ? FilledButton.tonal(onPressed: onTap, style: style, child: child)
        : OutlinedButton(onPressed: onTap, style: style, child: child);
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
    // 선택지가 셋이고 저마다 두 줄이다. 기본 높이 상한(화면의 9/16)에 걸리면
    // 글자 크기를 키운 기기에서 마지막 선택지가 잘린다.
    isScrollControlled: true,
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
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          // 선택지가 시트 가로를 꽉 채우게 한다.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plant.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              plant.isSettled ? s.settledQuestion : s.soilQuestion,
              style: theme.textTheme.bodyMedium,
            ),
            // 깊이 안내는 흙 상태를 묻는 경우에만. 정착된 식물은 물을 줬는지
            // 아닌지를 묻는 것이라 흙을 파볼 필요가 없다.
            if (!plant.isSettled) ...[
              const SizedBox(height: 6),
              Text(
                s.soilDepthHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
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
