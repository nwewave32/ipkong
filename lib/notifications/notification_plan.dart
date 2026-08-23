import '../domain/models/enums.dart';
import '../domain/models/plant.dart';
import '../domain/watering_schedule.dart';

/// 알림의 형태. 어떤 버튼을 붙일지 결정한다.
enum NotificationStyle {
  /// 학습 중인 식물 하나 — 흙 상태 3택
  learning,

  /// 정착된 식물 하나 — 줬어요 / 아직 축축해요
  settled,

  /// 같은 날 확인할 식물이 둘 이상 — 액션 버튼 없이 앱을 연다
  digest,
}

/// 특정 날짜에 보낼 알림 하나.
class PlannedNotification {
  const PlannedNotification({
    required this.date,
    required this.plants,
    required this.style,
  });

  final DateTime date;
  final List<Plant> plants;
  final NotificationStyle style;

  List<String> get plantIds => plants.map((p) => p.id).toList();

  /// 날짜 기반의 안정적인 알림 ID.
  int get id => date.difference(DateTime.utc(2020)).inDays.abs() % 100000;
}

/// 알림 예약 계획을 세우는 순수 로직.
///
/// 플랫폼 API 를 전혀 모르므로 단위 테스트가 가능하다. 실제 예약은
/// `NotificationBackend` 구현체가 맡는다.
class NotificationPlanner {
  const NotificationPlanner._();

  /// 향후 며칠치를 예약할지.
  ///
  /// iOS 는 앱당 예약 알림을 **64개**까지만 유지하고 초과분을 조용히 버린다.
  /// 날짜당 1개씩 30일치면 최대 30개라 상한의 절반도 쓰지 않는다.
  /// 백그라운드 갱신에 의존하지 않으므로 한 달에 한 번만 앱을 열어도 유지된다.
  static const defaultHorizonDays = 30;

  /// 식물 목록으로부터 예약할 알림들을 만든다.
  ///
  /// **하루에 알림 하나**가 원칙이다. 알림 과부하 방지(제품 차별점)와
  /// iOS 예약 상한 대응이 이 규칙 하나로 동시에 해결된다.
  static List<PlannedNotification> build({
    required List<Plant> plants,
    required Climate climate,
    required bool winterModeEnabled,
    required DateTime now,
    int horizonDays = defaultHorizonDays,
  }) {
    final today = WateringSchedule.dateOnly(now);
    final horizon = today.add(Duration(days: horizonDays));

    final byDate = <DateTime, List<Plant>>{};
    for (final plant in plants) {
      if (plant.isArchived) continue;

      var due = WateringSchedule.nextNotifyDate(
        plant,
        today,
        climate: climate,
        winterModeEnabled: winterModeEnabled,
      );

      // 지난 일정은 빨간 배지로 쌓지 않고 조용히 오늘로 이월한다.
      // 밀린 항목이 누적되는 죄책감이 이탈의 주원인이다.
      if (due.isBefore(today)) due = today;
      if (due.isAfter(horizon)) continue;

      byDate.putIfAbsent(due, () => <Plant>[]).add(plant);
    }

    final dates = byDate.keys.toList()..sort();
    return [
      for (final date in dates)
        PlannedNotification(
          date: date,
          plants: byDate[date]!,
          style: _styleFor(byDate[date]!),
        ),
    ];
  }

  static NotificationStyle _styleFor(List<Plant> plants) {
    if (plants.length > 1) return NotificationStyle.digest;
    return plants.first.isSettled
        ? NotificationStyle.settled
        : NotificationStyle.learning;
  }
}
