import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// 30일치만 예약하므로 ±10년 데이터면 충분하다. latest_all 은 445KB,
// latest_10y 는 66KB — 쓰지도 않을 1970년대 규칙을 앱에 넣을 이유가 없다.
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_backend.dart';
import 'notification_plan.dart';
import 'pending_actions.dart';

/// 앱이 떠 있지 않을 때 알림 액션을 받는 진입점.
///
/// 별도 isolate 에서 불리므로 최상위 함수여야 하고, AOT 컴파일에서 잘려나가지
/// 않도록 `vm:entry-point` 를 붙여야 한다. 여기서는 DB 를 건드리지 않고
/// 큐에만 적어둔다 — 앱이 다음에 열릴 때 [PendingActions.drain] 이 반영한다.
///
/// ⚠️ 콜백 시그니처가 `void` 라 쓰기를 **기다릴 수 없다.** 플랫폼이 이 isolate
/// 를 먼저 정리하면 응답 하나가 사라질 수 있다 — 플러그인 API 의 제약이고 앱
/// 쪽에서 없앨 방법이 없다. 할 수 있는 건 두 가지다: 쓰기 전에 다른 일을 하지
/// 않아 창을 최대한 좁히는 것, 그리고 **실패를 조용히 삼키지 않는 것.**
/// 응답이 사라지면 사용자는 "버튼을 눌렀는데 아무 일도 없다"만 겪고, 로그가
/// 없으면 재현할 방법도 없다.
@pragma('vm:entry-point')
void ipkongBackgroundActionHandler(NotificationResponse response) {
  // 이 isolate 에는 플러그인이 등록돼 있지 않다. SharedPreferences 를 쓰려면
  // 먼저 등록해야 한다.
  DartPluginRegistrant.ensureInitialized();

  final actionId = response.actionId;
  final payload = response.payload;
  if (actionId == null || payload == null) return;

  PendingActions.enqueue(actionId, payload).catchError((Object e) {
    debugPrint('[ipkong] 백그라운드 액션을 큐에 넣지 못했습니다 ($actionId): $e');
  });
}

/// `flutter_local_notifications` 22.x 를 쓰는 실제 알림 구현.
///
/// 언제 무엇을 보낼지는 [NotificationPlanner] 가 이미 정해서 넘겨준다.
/// 이 클래스는 그 계획을 플랫폼 API 로 옮기기만 한다.
class LocalNotificationBackend implements NotificationBackend {
  LocalNotificationBackend({this.timeZoneName});

  /// 기기의 IANA 타임존 이름 (예: `Asia/Seoul`). main() 이 기후대 판정을 위해
  /// 이미 구한 값을 그대로 받는다 — 플랫폼 호출을 두 번 할 이유가 없다.
  final String? timeZoneName;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Android 알림 채널. 사용자가 설정에서 보게 되는 이름이다.
  // TODO(l10n): 채널 이름·설명과 [NotificationCopy] 가 아직 한국어 하드코딩이다.
  //  영어 알림은 체크리스트 C 의 별도 항목으로 남아 있다.
  static const _channelId = 'ipkong_watering';
  static const _channelName = '물주기 알림';
  static const _channelDescription = '하루 한 번, 오늘 확인할 식물만 알려드립니다.';

  /// Android 상태바 아이콘. 알파 채널만 쓰는 단색 실루엣이어야 한다.
  static const _androidIcon = 'ic_notification';

  /// iOS 액션 버튼은 알림마다 붙이는 게 아니라 **카테고리**로 미리 등록하고,
  /// 알림은 카테고리 ID 만 지목한다. 그래서 init 시점에 다 만들어 둔다.
  static const _categoryLearning = 'ipkong_learning';
  static const _categorySettled = 'ipkong_settled';

  /// 정시 알람(`SCHEDULE_EXACT_ALARM`)을 쓰지 않는다.
  ///
  /// Android 14+ 에서 정시 알람은 알람시계·캘린더 앱에만 허용되고, Play 심사에서
  /// 별도 승인을 받아야 한다. 물주기 알림은 해당하지 않아 신청해도 거절될 뿐
  /// 아니라 권한 자체가 기본 거부로 내려온다. `inexactAllowWhileIdle` 은
  /// 권한이 필요 없고 Doze 중에도 실행되며, 오차는 길어야 십수 분이다 —
  /// 하루에 한 번 흙을 만져보라는 알림에 초 단위 정확도는 의미가 없다.
  static const _scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;

  @override
  Future<void> init({
    required void Function(String actionId, String payload) onAction,
  }) async {
    tzdata.initializeTimeZones();
    _setLocalLocation();

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings(_androidIcon),
        iOS: DarwinInitializationSettings(
          // 여기서 권한을 묻지 않는다. 앱을 켜자마자 시스템 팝업이 뜨면
          // 무엇에 대한 허락인지 모른 채 거절하게 된다. 온보딩을 마친 뒤
          // [HomeShell] 이 requestPermissions() 를 부른다.
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
          notificationCategories: _darwinCategories,
        ),
      ),
      // 앱이 떠 있을 때: 곧장 반영한다.
      onDidReceiveNotificationResponse: (response) {
        final actionId = response.actionId;
        final payload = response.payload;
        // actionId 가 없으면 본문을 탭한 것이다 — 앱이 열리는 것으로 충분하다.
        if (actionId == null || payload == null) return;
        onAction(actionId, payload);
      },
      // 앱이 죽어 있거나 백그라운드일 때: 큐에 적어둔다.
      onDidReceiveBackgroundNotificationResponse: ipkongBackgroundActionHandler,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            // 헤드업으로 화면을 가로채지 않는다. 알림 과부하를 만들지 않는 것이
            // 이 앱의 존재 이유다.
            importance: Importance.defaultImportance,
          ),
        );
  }

  @override
  Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Android 13+ 만 해당한다. 그 아래 버전에서는 null 이 돌아온다.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> reschedule(
    List<PlannedNotification> plan, {
    required int hour,
    required int minute,
  }) async {
    // 이미 떠 있는 알림은 건드리지 않고 예약분만 지운다. 사용자가 아직 응답하지
    // 않은 알림을 앱을 열었다는 이유로 치워버리면 그 응답을 영영 못 받는다.
    await _plugin.cancelAllPendingNotifications();

    final now = DateTime.now();
    for (final n in plan) {
      final at = DateTime(n.date.year, n.date.month, n.date.day, hour, minute);

      // 지난 시각으로 예약하면 Android 는 즉시 울리고 iOS 는 조용히 버린다.
      // 어느 쪽도 원하는 동작이 아니다. 계획 단계에서
      // [NotificationPlanner.rollPastSlotsForward] 가 이미 걸러내지만,
      // 여기서도 막아 둔다 — 실패가 조용해서 눈치채기 어려운 종류의 버그다.
      if (!at.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        title: NotificationCopy.title(n),
        body: NotificationCopy.body(n),
        payload: n.payload,
        androidScheduleMode: _scheduleMode,
        notificationDetails: _detailsFor(n.style),
      );
    }
  }

  /// 예약 시각을 기기 타임존으로 해석하기 위해 `tz.local` 을 맞춰 둔다.
  void _setLocalLocation() {
    final name = timeZoneName;
    if (name == null) {
      debugPrint('[ipkong] 타임존을 알 수 없어 UTC 기준으로 예약합니다');
      return;
    }
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // tz.local 은 UTC 로 남는다. 예약 시각은 Dart DateTime(기기 로컬)에서
      // 절대 시각으로 변환해 넘기므로, 존이 UTC 여도 울리는 순간은 같다.
      debugPrint('[ipkong] 알 수 없는 타임존: $name — UTC 기준으로 예약합니다');
    }
  }

  static final List<DarwinNotificationCategory> _darwinCategories = [
    DarwinNotificationCategory(
      _categoryLearning,
      actions: _darwinActions(NotificationStyle.learning),
    ),
    DarwinNotificationCategory(
      _categorySettled,
      actions: _darwinActions(NotificationStyle.settled),
    ),
    // digest 는 액션이 없다 — 여러 식물을 알림 버튼 하나로 답할 수 없으므로
    // 앱을 열어 하나씩 답하게 한다. 카테고리도 붙이지 않는다.
  ];

  /// `.plain` 은 옵션을 주지 않으면 앱을 열지 않고 처리된다.
  /// 흙 상태 한 번 답하자고 앱이 뜰 이유가 없다.
  static List<DarwinNotificationAction> _darwinActions(
    NotificationStyle style,
  ) =>
      [
        for (final (id, title) in NotificationCopy.actions(style))
          DarwinNotificationAction.plain(id, title),
      ];

  NotificationDetails _detailsFor(NotificationStyle style) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          actions: [
            for (final (id, title) in NotificationCopy.actions(style))
              AndroidNotificationAction(
                id,
                title,
                // 앱을 열지 않고 백그라운드 콜백으로 넘긴다.
                showsUserInterface: false,
                cancelNotification: true,
              ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: switch (style) {
            NotificationStyle.learning => _categoryLearning,
            NotificationStyle.settled => _categorySettled,
            NotificationStyle.digest => null,
          },
        ),
      );
}
