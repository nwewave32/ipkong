import 'package:flutter_test/flutter_test.dart';
import 'package:ipkong/domain/models/enums.dart';
import 'package:ipkong/domain/models/plant.dart';
import 'package:ipkong/notifications/notification_plan.dart';

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
}
