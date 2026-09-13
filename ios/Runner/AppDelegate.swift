import Flutter
import UIKit
import UserNotifications
// setPluginRegistrantCallback 를 부르기 위해 필요하다.
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 앱이 포그라운드일 때도 알림을 띄우고, 알림 액션을 앱으로 전달받는다.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // 알림 액션은 앱을 열지 않고 별도 isolate 에서 처리된다. 그 isolate 에도
    // 플러그인을 등록해 줘야 SharedPreferences 로 큐에 적을 수 있다.
    // 이 앱은 UIScene 생명주기를 쓰므로 didFinishLaunching 이 아니라
    // 여기에 둔다.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
