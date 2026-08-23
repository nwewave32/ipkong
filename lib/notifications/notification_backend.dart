import 'package:flutter/foundation.dart';

import 'notification_plan.dart';

/// 알림 액션 ID. 백그라운드 콜백에서도 쓰이므로 최상위 상수로 둔다.
const kActionTooWet = 'too_wet';
const kActionJustRight = 'just_right';
const kActionTooDry = 'too_dry';
const kActionWatered = 'watered';

/// 알림 문구. 백엔드 구현체가 가져다 쓴다.
class NotificationCopy {
  const NotificationCopy._();

  static String title(PlannedNotification n) => switch (n.style) {
        NotificationStyle.digest => '오늘 확인할 식물 ${n.plants.length}개',
        NotificationStyle.learning => '${n.plants.first.name} 흙 한번 만져보세요',
        NotificationStyle.settled => '${n.plants.first.name}에 물 줄 시간이에요',
      };

  static String? body(PlannedNotification n) => switch (n.style) {
        NotificationStyle.digest => n.plants.map((p) => p.name).join(', '),
        NotificationStyle.learning => '어땠나요?',
        NotificationStyle.settled => null,
      };

  /// (actionId, 표시 문구) 목록. digest 에는 액션을 붙이지 않는다.
  static List<(String, String)> actions(NotificationStyle style) =>
      switch (style) {
        NotificationStyle.digest => const [],
        NotificationStyle.learning => const [
            (kActionTooWet, '축축했어요'),
            (kActionJustRight, '적당했어요'),
            (kActionTooDry, '바짝 말랐어요'),
          ],
        NotificationStyle.settled => const [
            (kActionWatered, '줬어요'),
            (kActionTooWet, '아직 축축해요'),
          ],
      };
}

/// 플랫폼 알림 구현의 경계.
///
/// 이 인터페이스 뒤에만 `flutter_local_notifications` 가 존재한다.
/// 패키지 API 가 바뀌어도 앱의 나머지는 영향을 받지 않는다.
abstract class NotificationBackend {
  Future<void> init({
    required void Function(String actionId, String payload) onAction,
  });

  Future<void> requestPermissions();

  /// 기존 예약을 모두 지우고 [plan] 대로 다시 예약한다.
  Future<void> reschedule(
    List<PlannedNotification> plan, {
    required int hour,
    required int minute,
  });
}

/// 실제 알림을 보내지 않고 로그만 남기는 구현.
///
/// 알림 백엔드가 아직 붙지 않아도 앱 전체가 동작하고 테스트가 돌아가도록
/// 하기 위한 것이다. 실기기 알림이 필요해지면 `LocalNotificationBackend`
/// 로 갈아끼우면 된다 (`main.dart` 한 줄).
class DebugNotificationBackend implements NotificationBackend {
  @override
  Future<void> init({
    required void Function(String actionId, String payload) onAction,
  }) async {
    debugPrint('[ipkong] DebugNotificationBackend 사용 중 — 실제 알림은 가지 않습니다');
  }

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> reschedule(
    List<PlannedNotification> plan, {
    required int hour,
    required int minute,
  }) async {
    debugPrint('[ipkong] 알림 ${plan.length}건 예약 (${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')})');
    for (final n in plan) {
      debugPrint('  ${n.date.toIso8601String().substring(0, 10)}  '
          '[${n.style.name}] ${NotificationCopy.title(n)}');
    }
  }
}
