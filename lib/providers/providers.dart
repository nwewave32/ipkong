import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/climate.dart';
import '../data/app_database.dart';
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

/// 알림 백엔드. main() 에서 오버라이드한다.
final notificationBackendProvider = Provider<NotificationBackend>(
  (ref) => DebugNotificationBackend(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

final plantRepositoryProvider = Provider<PlantRepository>((ref) {
  final settings = ref.watch(settingsRepositoryProvider);
  return PlantRepository(AppDatabase.instance, settings.deviceId);
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

/// 식물 목록 + 모든 변경 진입점.
class PlantListNotifier extends StateNotifier<AsyncValue<List<Plant>>> {
  PlantListNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  final Ref _ref;

  PlantRepository get _repo => _ref.read(plantRepositoryProvider);
  Climate get _climate => _ref.read(climateProvider);
  bool get _winter => _ref.read(winterModeProvider);

  Future<void> load() async {
    try {
      final plants = await _repo.listActive();
      state = AsyncValue.data(plants);
      await _reschedule(plants);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addPlant({
    required String name,
    required PlantKind kind,
    required LightLevel light,
    double? userIntervalDays,
    String? photoPath,
  }) async {
    final now = DateTime.now();
    final isWinterNow = _winter && ClimateResolver.isWinter(now, _climate);

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
      photoPath: photoPath,
      now: now,
    );
    await load();
  }

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
  Future<void> editPlant({
    required String plantId,
    required String name,
    required PlantKind kind,
    required LightLevel light,
    double? userIntervalDays,
    String? photoPath,
    bool clearPhoto = false,
  }) async {
    final plant = await _repo.findById(plantId);
    if (plant == null) return;

    final now = DateTime.now();
    await _repo.update(
      WateringSchedule.applyEdit(
        plant,
        name: name,
        kind: kind,
        light: light,
        userIntervalDays: userIntervalDays,
        photoPath: photoPath,
        clearPhoto: clearPhoto,
        isWinterNow: _winter && ClimateResolver.isWinter(now, _climate),
        now: now,
      ),
    );
    await load(); // 식물 변경은 재예약 트리거다
  }

  Future<void> archive(String plantId) async {
    await _repo.archive(plantId);
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
    final settings = _ref.read(settingsRepositoryProvider);
    final plan = NotificationPlanner.build(
      plants: plants,
      climate: _climate,
      winterModeEnabled: _winter,
      now: DateTime.now(),
    );
    await _ref.read(notificationBackendProvider).reschedule(
          plan,
          hour: settings.notifyHour,
          minute: settings.notifyMinute,
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
