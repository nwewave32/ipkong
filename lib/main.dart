import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/climate.dart';
import 'core/local_timezone.dart';
import 'notifications/notification_backend.dart';
import 'providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // 기후대 판정. 실패해도 북반구로 떨어질 뿐이고, 어차피 겨울 확인 카드가
  // 사용자에게 되묻기 때문에 치명적이지 않다.
  final tzName = await resolveLocalTimezoneName();
  final climate = ClimateResolver.resolve(tzName);
  debugPrint('[ipkong] timezone=$tzName climate=$climate');

  // 실기기 알림을 붙일 때 이 한 줄을 LocalNotificationBackend() 로 바꾼다.
  final NotificationBackend backend = DebugNotificationBackend();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      climateProvider.overrideWithValue(climate),
      notificationBackendProvider.overrideWithValue(backend),
    ],
  );

  await backend.init(
    onAction: (actionId, payload) {
      container.read(plantListProvider.notifier).handleAction(actionId, payload);
    },
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const IpkongApp(),
    ),
  );
}
