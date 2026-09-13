import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/climate.dart';
import '../data/app_database.dart';
import '../data/photo_store.dart';
import '../data/plant_repository.dart';
import '../data/settings_repository.dart';
import '../domain/models/enums.dart';
import '../domain/models/plant.dart';
import '../domain/watering_schedule.dart';
import '../notifications/notification_backend.dart';
import '../notifications/notification_plan.dart';
import '../notifications/pending_actions.dart';

/// main() 에서 오버라이드해 주입한다.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main() 에서 override 해야 합니다'),
);

/// 앱 시작 시 판정된 기후대. main() 에서 오버라이드한다.
final climateProvider = Provider<Climate>((ref) => Climate.northern);

/// 알림 백엔드. main() 이 [LocalNotificationBackend] 로 오버라이드한다.
///
/// 기본값을 Debug 로 두는 것은 의도적이다. 위젯 테스트는 이 프로바이더를
/// 오버라이드하지 않으므로, 기본값이 실제 구현이면 테스트가 플랫폼 채널을
/// 부르다 죽는다.
final notificationBackendProvider = Provider<NotificationBackend>(
  (ref) => DebugNotificationBackend(),
);

/// 사진 보관소. main() 이 문서 폴더를 연 뒤 오버라이드한다.
///
/// 기본값은 "쓸 수 없음" 이다. 폴더를 여는 건 비동기라 프로바이더 기본값으로는
/// 만들 수 없고, 테스트에서 사진은 없는 것으로 취급되면 그만이다.
final photoStoreProvider = Provider<PhotoStore>(
  (ref) => const PhotoStore.unavailable(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

final plantRepositoryProvider = Provider<PlantRepository>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return PlantRepository(AppDatabase.instance, settings.deviceId);
});

/// 알림 시각. 바꾸면 즉시 재예약이 돌아간다.
///
/// [SettingsRepository] 는 SharedPreferences 를 감싼 평범한 클래스라
/// 값이 바뀌어도 Riverpod 에 알리지 않는다. 저장소를 직접 watch 하면
/// **저장은 되는데 화면이 옛 값을 계속 보여준다.** 겨울 모드·언어와 같은
/// 방식으로 화면이 바라볼 상태를 따로 둔다.
final notifyTimeProvider = StateProvider<TimeOfDay>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return TimeOfDay(hour: settings.notifyHour, minute: settings.notifyMinute);
});

/// 겨울 모드 on/off. 바꾸면 즉시 재예약이 돌아간다.
final winterModeProvider = StateProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).winterModeEnabled,
);

/// 앱 로케일. null 이면 시스템을 따른다.
final localeProvider = StateProvider<Locale?>((ref) {
  final code = ref.watch(settingsRepositoryProvider).localeCode;
  return code == null ? null : Locale(code);
});

/// 온보딩을 마쳤는가. false 면 [IpkongApp] 이 온보딩을 첫 화면으로 띄운다.
final onboardingDoneProvider = StateProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).onboardingDone,
);

/// 온보딩 마지막 화면에서 "식물 등록하기"로 나온 경우 true.
///
/// 명세 §3 의 첫 실행 플로우는 온보딩 다음이 곧장 식물 추가다.
/// [HomeShell] 이 첫 프레임 뒤에 이 플래그를 읽고 추가 화면을 띄운 뒤 내린다.
final startAddPlantProvider = StateProvider<bool>((ref) => false);

/// 저장 결과.
///
/// 사진 복사만 실패하는 경우가 있다 (저장공간 부족, 원본이 사라짐). 나머지는
/// 멀쩡히 저장됐으므로 저장 자체를 실패로 되돌리는 건 과하지만, **조용히 넘어가면
/// 사용자는 사진을 넣은 줄 알고 화면을 떠난다.** 화면이 알려줄 수 있게 구분해서
/// 돌려준다.
enum SaveOutcome { ok, savedWithoutPhoto }

/// 식물 목록 + 모든 변경 진입점.
class PlantListNotifier extends StateNotifier<AsyncValue<List<Plant>>> {
  PlantListNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  final Ref _ref;

  PlantRepository get _repo => _ref.read(plantRepositoryProvider);
  PhotoStore get _photos => _ref.read(photoStoreProvider);
  Climate get _climate => _ref.read(climateProvider);
  bool get _winter => _ref.read(winterModeProvider);

  Future<void> load() async {
    final List<Plant> plants;
    try {
      plants = await _repo.listActive();
      state = AsyncValue.data(plants);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return;
    }

    // 재예약은 목록과 성패를 공유하지 않는다.
    //
    // 여기서 던지는 건 플랫폼 알림 API 다 (재개할 때마다 최대 30번 호출한다).
    // 그 한 번이 실패했다고 이미 멀쩡히 읽어온 식물 목록을 버리고 에러 화면을
    // 띄우면, 알림이 안 온 게 아니라 앱이 통째로 망가진 것처럼 보인다.
    try {
      await _reschedule(plants);
    } catch (e, st) {
      debugPrint('[ipkong] 알림 재예약 실패 — 목록은 그대로 둡니다: $e\n$st');
    }
  }

  Future<SaveOutcome> addPlant({
    required String name,
    required PlantKind kind,
    required LightLevel light,
    double? userIntervalDays,
    String? photoPath,
  }) async {
    final now = DateTime.now();
    final isWinterNow = _winter && ClimateResolver.isWinter(now, _climate);
    final adopted = await _photos.adopt(photoPath);

    // 사용자가 입력했으면 그 값을 그대로 기준으로 쓴다.
    // anchorInWinter 를 함께 기록해 두면 계절이 바뀔 때만 배율이 붙는다.
    await _repo.create(
      name: name,
      kind: kind,
      light: light,
      anchorDays: userIntervalDays ?? WateringSchedule.baselineDays(kind, light),
      anchorSource:
          userIntervalDays == null ? AnchorSource.table : AnchorSource.user,
      anchorInWinter: userIntervalDays == null ? false : isWinterNow,
      // 폼은 여기까지 임시 경로를 들고 온다. 저장하는 이 순간에 문서 폴더로
      // 복사한다 — 고르자마자 복사하면 취소한 사진이 쓰레기로 남는다.
      photoPath: adopted,
      now: now,
    );
    await load();
    return _photoOutcome(requested: photoPath, adopted: adopted);
  }

  /// 사진을 넣으려 했는데 못 들인 경우만 골라낸다.
  ///
  /// 이미 저장소의 파일이면 [PhotoStore.adopt] 가 같은 이름을 그대로 돌려주므로
  /// (이름만 고치러 들어온 경우) 여기서 실패로 잡히지 않는다.
  static SaveOutcome _photoOutcome({
    required String? requested,
    required String? adopted,
  }) =>
      requested != null && adopted == null
          ? SaveOutcome.savedWithoutPhoto
          : SaveOutcome.ok;

  Future<void> respond(String plantId, SoilResponse response) async {
    final plant = await _repo.findById(plantId);
    if (plant == null) return;

    final now = DateTime.now();
    await _repo.update(WateringSchedule.applyResponse(plant, response, now));
    await _repo.appendEvent(
      plantId: plantId,
      type: response.eventType,
      occurredAt: now,
    );
    await load();
  }

  /// 알림 없이 직접 물을 준 경우. 예정보다 이르면 단축 신호로 처리된다.
  Future<void> waterNow(String plantId) async {
    final plant = await _repo.findById(plantId);
    if (plant == null) return;

    final now = DateTime.now();
    await _repo.update(
      WateringSchedule.applyManualWatering(
        plant,
        now,
        climate: _climate,
        winterModeEnabled: _winter,
      ),
    );
    await _repo.appendEvent(
      plantId: plantId,
      type: EventType.watered,
      occurredAt: now,
    );
    await load();
  }

  Future<void> relocate(String plantId, LightLevel light) async {
    final plant = await _repo.findById(plantId);
    if (plant == null) return;
    await _repo.update(
      WateringSchedule.relocate(plant, light, DateTime.now()),
    );
    await load();
  }

  /// 수정 화면의 저장.
  ///
  /// 어떤 항목에 어떤 규칙을 태울지는 [WateringSchedule.applyEdit] 이
  /// 순수 함수로 정한다. 여기는 읽고·쓰고·재예약만 한다.
  Future<SaveOutcome> editPlant({
    required String plantId,
    required String name,
    required PlantKind kind,
    required LightLevel light,
    double? userIntervalDays,
    String? photoPath,
    bool clearPhoto = false,
  }) async {
    final plant = await _repo.findById(plantId);
    if (plant == null) return SaveOutcome.ok;

    final now = DateTime.now();
    final previousPhoto = plant.photoPath;
    final adopted = await _photos.adopt(photoPath);

    await _repo.update(
      WateringSchedule.applyEdit(
        plant,
        name: name,
        kind: kind,
        light: light,
        userIntervalDays: userIntervalDays,
        photoPath: adopted,
        clearPhoto: clearPhoto,
        isWinterNow: _winter && ClimateResolver.isWinter(now, _climate),
        now: now,
      ),
    );

    // 저장이 끝난 뒤에 옛 파일을 지운다. 순서를 뒤집으면 DB 쓰기가 실패했을 때
    // 사진만 사라진 식물이 남는다.
    //
    // [WateringSchedule.applyEdit] 은 photoPath 가 null 이면 "안 바꿈" 으로
    // 해석하므로(지우기는 clearPhoto 가 맡는다), 실제로 남은 값이 무엇인지
    // 같은 규칙으로 되짚어야 멀쩡한 사진을 지우지 않는다.
    final remaining = clearPhoto ? null : (adopted ?? previousPhoto);
    if (previousPhoto != null && previousPhoto != remaining) {
      await _photos.deleteQuietly(previousPhoto);
    }

    await load(); // 식물 변경은 재예약 트리거다
    return _photoOutcome(requested: photoPath, adopted: adopted);
  }

  /// 아카이브는 이벤트 로그를 지키기 위한 것이지 사진을 지키기 위한 게 아니다.
  /// 사용자 눈에는 '삭제'를 누른 것이므로, 사진 파일은 실제로 지운다.
  /// DB 의 경로도 함께 비워 없는 파일을 가리키지 않게 한다.
  Future<void> archive(String plantId) async {
    final plant = await _repo.findById(plantId);
    final photo = plant?.photoPath;
    if (plant != null && photo != null) {
      await _repo.update(
        plant.copyWith(clearPhotoPath: true, updatedAt: DateTime.now()),
      );
    }
    await _repo.archive(plantId);
    await _photos.deleteQuietly(photo);
    await load();
  }

  /// 계절이 바뀌면 정착을 풀어 새 주기를 한 번 검증하게 한다.
  Future<void> onWinterModeChanged() async {
    final plants = await _repo.listActive();
    final now = DateTime.now();
    for (final p in plants) {
      await _repo.update(WateringSchedule.resetSettlingForSeasonChange(p, now));
    }
    await load();
  }

  /// 백그라운드 알림 액션 큐를 비운다.
  Future<void> drainPendingNotificationActions() async {
    for (final action in await PendingActions.drain()) {
      if (action.response != null) {
        await respond(action.plantId, action.response!);
      } else {
        await waterNow(action.plantId);
      }
    }
  }

  /// 알림 액션 하나를 즉시 반영한다 (앱이 떠 있을 때).
  Future<void> handleAction(String actionId, String payload) async {
    final action = PendingActions.parse(actionId, payload);
    if (action == null) return;
    if (action.response != null) {
      await respond(action.plantId, action.response!);
    } else {
      await waterNow(action.plantId);
    }
  }

  /// 재예약 트리거:
  ///  - 앱이 포그라운드로 들어올 때
  ///  - 알림 액션을 처리했을 때
  ///  - 식물을 추가·수정·삭제했을 때
  ///  - 겨울 모드가 전환됐을 때
  Future<void> _reschedule(List<Plant> plants) async {
    final notifyAt = _ref.read(notifyTimeProvider);
    final now = DateTime.now();
    // 계획을 세운 뒤, 오늘치 알림 시각이 이미 지났으면 다음 날로 넘긴다.
    // 백엔드에는 항상 "미래의 계획"만 넘어간다.
    final plan = NotificationPlanner.rollPastSlotsForward(
      NotificationPlanner.build(
        plants: plants,
        climate: _climate,
        winterModeEnabled: _winter,
        now: now,
      ),
      now: now,
      hour: notifyAt.hour,
      minute: notifyAt.minute,
    );
    await _ref.read(notificationBackendProvider).reschedule(
          plan,
          hour: notifyAt.hour,
          minute: notifyAt.minute,
        );
  }
}

final plantListProvider =
    StateNotifierProvider<PlantListNotifier, AsyncValue<List<Plant>>>(
  PlantListNotifier.new,
);

/// 오늘 확인해야 하는 식물들.
final todayPlantsProvider = Provider<List<Plant>>((ref) {
  final plants = ref.watch(plantListProvider).value ?? const <Plant>[];
  final climate = ref.watch(climateProvider);
  final winter = ref.watch(winterModeProvider);
  final today = WateringSchedule.dateOnly(DateTime.now());

  return plants.where((p) {
    final due = WateringSchedule.nextNotifyDate(
      p,
      today,
      climate: climate,
      winterModeEnabled: winter,
    );
    return !due.isAfter(today); // 지난 것도 오늘로 이월
  }).toList();
});
