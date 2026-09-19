import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipkong/domain/models/enums.dart';
import 'package:ipkong/domain/models/plant.dart';
import 'package:ipkong/notifications/notification_backend.dart';
import 'package:ipkong/notifications/notification_plan.dart';
import 'package:ipkong/notifications/pending_actions.dart';

final d0 = DateTime(2026, 6, 1); // 북반구 여름 — 계절 배율 없음

Plant makePlant({
  required String id,
  double anchorDays = 10,
  bool isSettled = false,
  bool isArchived = false,
  DateTime? createdAt,
}) {
  final ts = createdAt ?? d0;
  return Plant(
    id: id,
    name: id,
    kind: PlantKind.normal,
    light: LightLevel.medium,
    anchorDays: anchorDays,
    anchorSource: AnchorSource.table,
    anchorInWinter: false,
    createdAt: ts,
    updatedAt: ts,
    isSettled: isSettled,
    isArchived: isArchived,
  );
}

List<PlannedNotification> plan(List<Plant> plants, {int horizonDays = 30}) =>
    NotificationPlanner.build(
      plants: plants,
      climate: Climate.northern,
      winterModeEnabled: true,
      now: d0,
      horizonDays: horizonDays,
    );

void main() {
  group('하루 1개 원칙', () {
    test('같은 날 예정인 식물들은 알림 하나로 묶인다', () {
      final result = plan([
        makePlant(id: 'a', anchorDays: 10),
        makePlant(id: 'b', anchorDays: 10),
        makePlant(id: 'c', anchorDays: 10),
      ]);

      expect(result, hasLength(1));
      expect(result.single.plants, hasLength(3));
      expect(result.single.style, NotificationStyle.digest);
    });

    test('다른 날이면 알림이 나뉜다', () {
      final result = plan([
        makePlant(id: 'a', anchorDays: 5),
        makePlant(id: 'b', anchorDays: 10),
      ]);

      expect(result, hasLength(2));
      expect(result.first.date.isBefore(result.last.date), isTrue);
    });

    test('식물이 하나면 학습/정착에 따라 스타일이 갈린다', () {
      expect(
        plan([makePlant(id: 'a')]).single.style,
        NotificationStyle.learning,
      );
      expect(
        plan([makePlant(id: 'a', isSettled: true)]).single.style,
        NotificationStyle.settled,
      );
    });
  });

  group('iOS 64개 상한 대응', () {
    test('예약 개수가 지평선 일수를 넘지 않는다', () {
      // 식물 50개가 제각기 다른 날에 예정돼 있어도
      // 날짜당 1개이므로 최대 30개다.
      final plants = [
        for (var i = 0; i < 50; i++)
          makePlant(id: 'p$i', anchorDays: (i % 40) + 2.0),
      ];

      final result = plan(plants);
      expect(result.length, lessThanOrEqualTo(30));
      expect(result.length, lessThan(64), reason: 'iOS 예약 상한');
    });

    test('지평선 밖의 일정은 예약하지 않는다', () {
      final result = plan([makePlant(id: 'far', anchorDays: 60)]);
      expect(result, isEmpty);
    });

    test('날짜가 중복되지 않는다', () {
      final plants = [
        for (var i = 0; i < 40; i++)
          makePlant(id: 'p$i', anchorDays: (i % 20) + 2.0),
      ];
      final dates = plan(plants).map((n) => n.date).toList();
      expect(dates.toSet().length, dates.length);
    });
  });

  group('밀린 일정 처리', () {
    test('지난 일정은 쌓이지 않고 오늘로 이월된다', () {
      // 한참 전에 등록해 이미 예정일이 지난 식물
      final overdue = makePlant(
        id: 'overdue',
        anchorDays: 5,
        createdAt: d0.subtract(const Duration(days: 90)),
      );

      final result = plan([overdue]);
      expect(result, hasLength(1));
      expect(result.single.date, d0);
    });

    test('밀린 식물들은 서로 다른 주기여도 오늘 하나로 묶인다', () {
      final result = plan([
        makePlant(
          id: 'overdue_a',
          anchorDays: 5,
          createdAt: d0.subtract(const Duration(days: 90)),
        ),
        makePlant(
          id: 'overdue_b',
          anchorDays: 12,
          createdAt: d0.subtract(const Duration(days: 60)),
        ),
      ]);

      expect(result, hasLength(1));
      expect(result.single.date, d0);
      expect(result.single.plants, hasLength(2));
      expect(result.single.style, NotificationStyle.digest);
    });
  });

  test('보관된 식물은 예약에서 빠진다', () {
    final result = plan([
      makePlant(id: 'active'),
      makePlant(id: 'archived', isArchived: true),
    ]);
    expect(result.single.plants.map((p) => p.id), ['active']);
  });

  test('알림 ID 는 날짜별로 안정적이고 서로 다르다', () {
    final plants = [
      for (var i = 0; i < 20; i++) makePlant(id: 'p$i', anchorDays: i + 2.0),
    ];
    final result = plan(plants);
    final ids = result.map((n) => n.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'ID 충돌');

    // 같은 입력이면 같은 ID
    expect(plan(plants).map((n) => n.id).toList(), ids);
  });

  group('payload — 백그라운드 액션이 되읽는 형식', () {
    test('식물 하나면 PendingActions 가 그 식물로 해석한다', () {
      final n = plan([makePlant(id: 'plant-1')]).single;

      expect(jsonDecode(n.payload), {
        'plantIds': ['plant-1'],
      });

      final parsed = PendingActions.parse(kActionTooWet, n.payload);
      expect(parsed, isNotNull);
      expect(parsed!.plantId, 'plant-1');
      expect(parsed.response, SoilResponse.tooWet);
    });

    test('묶음 알림은 액션으로 해석되지 않는다', () {
      // 묶음에는 액션 버튼을 붙이지 않지만, 혹시 payload 가 흘러들어와도
      // 어느 식물의 응답인지 알 수 없으므로 조용히 무시해야 한다.
      final n = plan([makePlant(id: 'a'), makePlant(id: 'b')]).single;
      expect(n.style, NotificationStyle.digest);
      expect(PendingActions.parse(kActionTooWet, n.payload), isNull);
    });

    test('본문 탭 — 식물 하나면 그 식물 id 를 돌려준다', () {
      final n = plan([makePlant(id: 'plant-1')]).single;
      expect(PendingActions.singlePlantIdFrom(n.payload), 'plant-1');
    });

    test('본문 탭 — 묶음 알림은 고를 식물이 없다', () {
      final n = plan([makePlant(id: 'a'), makePlant(id: 'b')]).single;
      expect(PendingActions.singlePlantIdFrom(n.payload), isNull);
    });

    test('본문 탭 — 깨진 payload 는 조용히 null', () {
      expect(PendingActions.singlePlantIdFrom('not json'), isNull);
      expect(PendingActions.singlePlantIdFrom('{}'), isNull);
    });
  });

  group('본문 안내 문구', () {
    test('iOS 는 길게 누르기, Android 는 펼치기로 안내한다', () {
      expect(NotificationCopy.hint(longPress: true), contains('길게'));
      expect(NotificationCopy.hint(longPress: false), contains('펼'));
    });

    test('학습 중 알림은 질문 뒤에 안내가 붙는다', () {
      final n = plan([makePlant(id: 'a')]).single;
      expect(n.style, NotificationStyle.learning);
      expect(NotificationCopy.body(n, hint: '길게 눌러 바로 답하기'),
          '어땠나요? · 길게 눌러 바로 답하기');
      // 안내를 주지 않으면 예전 문구 그대로다.
      expect(NotificationCopy.body(n), '어땠나요?');
    });

    test('묶음 알림에는 안내를 붙이지 않는다', () {
      // 액션 버튼이 없는 알림이다. 안내가 붙으면 없는 버튼을 찾게 된다.
      final n = plan([makePlant(id: 'a'), makePlant(id: 'b')]).single;
      expect(n.style, NotificationStyle.digest);
      expect(NotificationCopy.body(n, hint: '길게 눌러 바로 답하기'), isNot(contains('길게')));
    });
  });

  group('지난 시각 이월', () {
    List<PlannedNotification> roll(
      List<PlannedNotification> input,
      DateTime now,
    ) =>
        NotificationPlanner.rollPastSlotsForward(
          input,
          now: now,
          hour: 9,
          minute: 0,
        );

    test('알림 시각이 지나기 전이면 그대로 둔다', () {
      final input = plan([makePlant(id: 'a', anchorDays: 10)]);
      final result = roll(input, DateTime(2026, 6, 1, 8, 59));
      expect(result.single.date, input.single.date);
    });

    test('오늘 시각이 지났으면 내일로 넘어간다', () {
      // 오늘이 예정일인데 오후에 앱을 열었다. 지난 시각으로 예약하면
      // Android 는 즉시 울리고 iOS 는 버린다 — 둘 다 원하지 않는다.
      final today = DateTime(2026, 6, 1);
      final input = [
        PlannedNotification(
          date: today,
          plants: [makePlant(id: 'a')],
          style: NotificationStyle.learning,
        ),
      ];

      final result = roll(input, DateTime(2026, 6, 1, 14, 0));
      expect(result.single.date, DateTime(2026, 6, 2));
      expect(result.single.plants.map((p) => p.id), ['a']);
    });

    test('넘어간 자리에 이미 알림이 있으면 합친다 — 하루 1개는 유지된다', () {
      final input = [
        PlannedNotification(
          date: DateTime(2026, 6, 1),
          plants: [makePlant(id: 'overdue')],
          style: NotificationStyle.learning,
        ),
        PlannedNotification(
          date: DateTime(2026, 6, 2),
          plants: [makePlant(id: 'tomorrow')],
          style: NotificationStyle.learning,
        ),
      ];

      final result = roll(input, DateTime(2026, 6, 1, 14, 0));

      expect(result, hasLength(1), reason: '같은 날 알림이 둘이 되면 안 된다');
      expect(result.single.date, DateTime(2026, 6, 2));
      expect(
        result.single.plants.map((p) => p.id),
        containsAll(['overdue', 'tomorrow']),
      );
      expect(result.single.style, NotificationStyle.digest);
    });

    test('정각은 아직 지나지 않은 것으로 보지 않는다', () {
      // 09:00 에 예약할 알림을 09:00 에 재예약하면 이미 울렸거나 울리는 중이다.
      final input = [
        PlannedNotification(
          date: DateTime(2026, 6, 1),
          plants: [makePlant(id: 'a')],
          style: NotificationStyle.learning,
        ),
      ];
      final result = roll(input, DateTime(2026, 6, 1, 9, 0));
      expect(result.single.date, DateTime(2026, 6, 2));
    });

    test('이월해도 ID 는 옮겨간 날짜를 따른다', () {
      final input = [
        PlannedNotification(
          date: DateTime(2026, 6, 1),
          plants: [makePlant(id: 'a')],
          style: NotificationStyle.learning,
        ),
      ];
      final rolled = roll(input, DateTime(2026, 6, 1, 14, 0)).single;

      final tomorrow = PlannedNotification(
        date: DateTime(2026, 6, 2),
        plants: [makePlant(id: 'b')],
        style: NotificationStyle.learning,
      );
      expect(rolled.id, tomorrow.id, reason: '같은 날짜면 같은 슬롯이어야 한다');
    });
  });
}
