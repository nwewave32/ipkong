import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/climate.dart';
import 'core/local_timezone.dart';
import 'data/photo_store.dart';
import 'notifications/local_notification_backend.dart';
import 'notifications/notification_backend.dart';
import 'notifications/pending_actions.dart';
import 'providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // 기후대 판정. 실패해도 북반구로 떨어질 뿐이고, 어차피 겨울 확인 카드가
  // 사용자에게 되묻기 때문에 치명적이지 않다.
  final tzName = await resolveLocalTimezoneName();
  final climate = ClimateResolver.resolve(tzName);
  debugPrint('[ipkong] timezone=$tzName climate=$climate');

  // 타임존 이름을 알림 백엔드에도 넘긴다. 예약 시각을 기기 타임존으로
  // 해석해야 하는데, 플랫폼 호출을 두 번 할 이유가 없다.
  final NotificationBackend backend =
      LocalNotificationBackend(timeZoneName: tzName);

  // 사진은 앱 문서 폴더에 둔다. 폴더를 여는 건 비동기라 프로바이더 기본값으로
  // 만들 수 없어서, 여기서 한 번 열고 주입한다.
  final photoStore = await PhotoStore.open();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      climateProvider.overrideWithValue(climate),
      notificationBackendProvider.overrideWithValue(backend),
      photoStoreProvider.overrideWithValue(photoStore),
    ],
  );

  await backend.init(
    onAction: (actionId, payload) {
      container.read(plantListProvider.notifier).handleAction(actionId, payload);
    },
    // 본문 탭에는 답이 실려 있지 않다. 반영할 게 없으니 어느 식물이었는지만
    // 적어두고, [HomeShell] 이 그 식물의 답변 시트를 띄운다.
    onOpen: (payload) {
      container.read(answerPromptPlantIdProvider.notifier).state =
          PendingActions.singlePlantIdFrom(payload);
    },
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const IpkongApp(),
    ),
  );
}
