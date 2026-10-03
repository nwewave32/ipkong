import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;

import '../l10n/app_localizations.dart';
import 'notification_plan.dart';

/// 알림 액션 ID. 백그라운드 콜백에서도 쓰이므로 최상위 상수로 둔다.
const kActionTooWet = 'too_wet';
const kActionJustRight = 'just_right';
const kActionTooDry = 'too_dry';
const kActionWatered = 'watered';

/// 알림 문구. 백엔드 구현체가 가져다 쓴다.
///
/// 정적 클래스였다가 [AppStrings] 를 받는 인스턴스가 됐다. 알림은 화면이
/// 하나도 없을 때(예약 시점·백그라운드) 만들어지므로 Localizations 를 쓸 수
/// 없고, 언어를 밖에서 넣어 주는 수밖에 없다.
class NotificationCopy {
  const NotificationCopy(this.s);

  NotificationCopy.of(Locale locale) : s = AppStrings(locale);

  final AppStrings s;

  String get channelName => s.notifyChannelName;
  String get channelDescription => s.notifyChannelDescription;

  String title(PlannedNotification n) => switch (n.style) {
        NotificationStyle.digest => s.notifyDigestTitle(n.plants.length),
        NotificationStyle.learning =>
          s.notifyLearningTitle(n.plants.first.name),
        NotificationStyle.settled => s.notifySettledTitle(n.plants.first.name),
      };

  /// 액션 버튼을 꺼내는 방법 안내.
  ///
  /// iOS 는 알림을 **길게 누르기 전에는 버튼이 아예 보이지 않는다.** 이걸 바꾸는
  /// 공개 API 가 없다 — 카테고리 액션은 펼친 알림에만 나오고, 잠금화면에 버튼을
  /// 붙여 보이게 하는 건 Live Activity 뿐인데 그건 서버 푸시가 있어야 띄운다.
  /// 그래서 본문 한 줄로 알려주는 것 말고는 발견시킬 방법이 없다.
  ///
  /// Android 는 펼치면 버튼이 바로 보이므로 동사만 다르다.
  String hint({required bool longPress}) => s.notifyHint(longPress: longPress);

  String? body(PlannedNotification n, {String? hint}) => switch (n.style) {
        // 묶음에는 액션이 없다. 안내를 붙이면 없는 버튼을 찾게 만든다.
        NotificationStyle.digest => n.plants.map((p) => p.name).join(', '),
        NotificationStyle.learning => hint == null
            ? s.notifyLearningBody
            : '${s.notifyLearningBody} · $hint',
        NotificationStyle.settled => hint,
      };

  /// (actionId, 표시 문구) 목록. digest 에는 액션을 붙이지 않는다.
  ///
  /// 문구는 앱 안 답변 시트와 **같은 것을 쓴다.** 알림 버튼을 눌러 답하든
  /// 시트에서 답하든 같은 말이어야 하고, 따로 두면 한쪽만 고치게 된다.
  List<(String, String)> actions(NotificationStyle style) => switch (style) {
        NotificationStyle.digest => const [],
        NotificationStyle.learning => [
            (kActionTooWet, s.tooWet),
            (kActionJustRight, s.justRight),
            (kActionTooDry, s.tooDry),
          ],
        NotificationStyle.settled => [
            (kActionWatered, s.watered),
            (kActionTooWet, s.stillMoist),
          ],
      };
}

/// 플랫폼 알림 구현의 경계.
///
/// 이 인터페이스 뒤에만 `flutter_local_notifications` 가 존재한다.
/// 패키지 API 가 바뀌어도 앱의 나머지는 영향을 받지 않는다.
abstract class NotificationBackend {
  /// [onAction] 은 액션 **버튼**을 누른 경우다 — 답이 실려 있으므로 곧장 반영한다.
  /// [onOpen] 은 알림 **본문**을 탭한 경우다 — 답은 없고 어느 식물의 알림이었는지만
  /// 알 수 있으므로, 앱이 그 식물의 답변 버튼을 꺼내주는 용도로만 쓴다.
  Future<void> init({
    required void Function(String actionId, String payload) onAction,
    required void Function(String payload) onOpen,
  });

  Future<void> requestPermissions();

  /// 앱 언어가 바뀌었다. 알림 쪽 문구를 다시 등록한다.
  ///
  /// 이것만으로는 **이미 예약된 알림의 제목·본문이 바뀌지 않는다.** 부른 쪽이
  /// 이어서 재예약까지 돌려야 한다 (`plantListProvider.load()`).
  Future<void> setLocale(Locale locale);

  /// 기존 예약을 모두 지우고 [plan] 대로 다시 예약한다.
  Future<void> reschedule(
    List<PlannedNotification> plan, {
    required int hour,
    required int minute,
  });
}

/// 실제 알림을 보내지 않고 로그만 남기는 구현.
///
/// 실기기에서는 `main.dart` 가 `LocalNotificationBackend` 를 주입한다.
/// 이 구현은 테스트용으로 남는다 — 위젯 테스트에서 플랫폼 채널을 부르지 않고
/// 예약 계획을 눈으로 확인할 수 있다.
class DebugNotificationBackend implements NotificationBackend {
  DebugNotificationBackend({Locale locale = const Locale('ko')})
      : _copy = NotificationCopy.of(locale);

  NotificationCopy _copy;

  @override
  Future<void> setLocale(Locale locale) async {
    _copy = NotificationCopy.of(locale);
    debugPrint('[ipkong] 알림 언어 → ${locale.languageCode}');
  }

  @override
  Future<void> init({
    required void Function(String actionId, String payload) onAction,
    required void Function(String payload) onOpen,
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
          '[${n.style.name}] ${_copy.title(n)}');
    }
  }
}
