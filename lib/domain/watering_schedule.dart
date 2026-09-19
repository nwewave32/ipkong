import 'dart:math' as math;

import '../core/climate.dart';
import 'models/enums.dart';
import 'models/plant.dart';

/// 물주기 알고리즘. 전부 순수 함수이므로 단위 테스트가 쉽다.
///
/// 핵심 식:
///
///     interval = anchorDays × seasonAdjust × factor
///
/// - `anchorDays`  기준값. 사용자 입력이거나 [baselineDays] 테이블 값.
/// - `seasonAdjust` 계절 보정. 학습이 아니라 **달력**에서 온다.
/// - `factor`      학습되는 유일한 값. 개인차만 흡수한다.
///
/// 계절을 factor 에게 배우게 하면 factor 가 계절 신호에 오염돼서
/// 정작 개인차를 못 배운다. 달력으로 아는 걸 데이터로 배울 이유가 없다.
class WateringSchedule {
  const WateringSchedule._();

  /// 정보가 전혀 없을 때의 기본 주기.
  ///
  /// 흔히 쓰이는 7일이 아니라 10일인 이유: 리스크가 비대칭이다.
  /// 짧으면 과습 → 뿌리 썩음 → **회복 불가**.
  /// 길면 잎이 처짐 → "바짝 말랐어요" 응답 → 단축 → **대개 생존**.
  /// 틀릴 거면 긴 쪽으로 틀린다.
  static const defaultAnchorDays = 10.0;

  /// 종류 × 광량 → 기준 주기(일). 평시(비겨울) 기준.
  static const _baseTable = <PlantKind, Map<LightLevel, double>>{
    PlantKind.succulent: {
      LightLevel.bright: 14,
      LightLevel.medium: 18,
      LightLevel.low: 25,
    },
    PlantKind.normal: {
      LightLevel.bright: 7,
      LightLevel.medium: 10,
      LightLevel.low: 14,
    },
    PlantKind.thinLeaf: {
      LightLevel.bright: 4,
      LightLevel.medium: 6,
      LightLevel.low: 8,
    },
  };

  static double baselineDays(PlantKind kind, LightLevel light) =>
      _baseTable[kind]![light]!;

  static double winterMultiplier(PlantKind kind) =>
      kind == PlantKind.succulent ? 1.9 : 1.4;

  /// 계절 보정 배율.
  ///
  /// [Plant.anchorInWinter] 와 지금의 겨울 여부가 같으면 1.0 이다.
  /// 즉 **주기를 정한 그 시점에는 항상 정한 값 그대로** 알림이 간다.
  /// 겨울에 입력한 값에 겨울 배율을 또 곱하는 이중 적용을 막는다.
  static double seasonAdjust(
    Plant p,
    DateTime now, {
    required Climate climate,
    required bool winterModeEnabled,
  }) {
    final isWinterNow =
        winterModeEnabled && ClimateResolver.isWinter(now, climate);
    if (isWinterNow == p.anchorInWinter) return 1.0;
    final mul = winterMultiplier(p.kind);
    return isWinterNow ? mul : 1 / mul;
  }

  /// 현재 주기(일).
  static int nextInterval(
    Plant p,
    DateTime now, {
    required Climate climate,
    required bool winterModeEnabled,
  }) {
    final adjust = seasonAdjust(
      p,
      now,
      climate: climate,
      winterModeEnabled: winterModeEnabled,
    );
    final raw = p.anchorDays * adjust * p.factor;
    return raw.round().clamp(2, 60);
  }

  /// 다음 알림 날짜.
  ///
  /// ★ 기산점은 "마지막 알림"이 아니라 **마지막 물 준 날**이다.
  /// 흙이 축축하다는 건 물을 안 줬다는 뜻이므로 시계가 리셋되지 않는다.
  ///
  /// 두 값 중 늦은 쪽을 고른다.
  ///
  /// | 후보 | 막는 실수 |
  /// |---|---|
  /// | `scheduleBase + interval` | `now + interval` 로 하면 "축축해요"를 누를 때마다 시계가 리셋되어 알림이 무한정 밀린다 |
  /// | `snoozeBase + minSnooze` | 연장 폭이 작을 때 다음 알림이 내일이 되는 걸 막는다 |
  ///
  /// ⚠️ 하한을 `now` 가 아니라 [Plant.snoozeBase] 에 묶는 것이 중요하다.
  /// `now` 로 두면 조회할 때마다 예정일이 뒤로 밀려서, 이미 밀린 식물의
  /// 알림이 **영영 오지 않는다.** 이 값은 조회 시점과 무관하게 안정적이다.
  ///
  /// 반환값이 과거일 수 있다(밀린 식물). 호출부에서 오늘로 이월하면 된다.
  static DateTime nextNotifyDate(
    Plant p,
    DateTime now, {
    required Climate climate,
    required bool winterModeEnabled,
  }) {
    final interval = nextInterval(
      p,
      now,
      climate: climate,
      winterModeEnabled: winterModeEnabled,
    );
    final byInterval = dateOnly(p.scheduleBase).add(Duration(days: interval));
    final floor = dateOnly(p.snoozeBase).add(Duration(days: minSnooze(interval)));
    return byInterval.isAfter(floor) ? byInterval : floor;
  }

  /// 최소 재확인 간격. 축축한 흙은 하루 만에 마르지 않는다.
  static int minSnooze(int interval) => math.max(2, (interval * 0.15).round());

  /// 사용자 응답을 반영한 새 [Plant] 를 돌려준다.
  ///
  /// | 응답        | 물 줌 | factor | 기산점 |
  /// |------------|------|--------|--------|
  /// | 축축했어요   | ✗    | 연장    | 유지    |
  /// | 적당했어요   | ✓    | 유지    | now    |
  /// | 바짝 말랐어요 | ✓    | 단축    | now    |
  static Plant applyResponse(Plant p, SoilResponse r, DateTime now) {
    final isUser = p.anchorSource == AnchorSource.user;

    // 주기를 직접 입력했다는 건 그 사람이 식물을 안다는 신호다.
    // 그러니 좁은 범위에서 작게만 움직인다.
    final lo = isUser ? 0.75 : 0.60;
    final hi = isUser ? 1.35 : 1.60;
    final step = isUser ? 0.10 : (p.eventCount < 3 ? 0.30 : 0.12);

    // 단축은 연장보다 크게. 과건조는 회복 가능하지만 과습은 회복 불가라,
    // 잘못된 방향이면 마른 쪽에서 빠져나오는 게 급하다.
    // 다만 초기 ±30% 구간에서 하한이 곧장 포화되지 않도록 상한을 둔다.
    final dryStep = math.min(step * 1.5, 0.35);

    var factor = p.factor;
    var settledStreak = p.settledStreak;
    var tooWetStreak = p.tooWetStreak;
    var lastWateredAt = p.lastWateredAt;

    if (r == SoilResponse.tooWet) {
      factor *= 1 + step;
      settledStreak = 0;
      tooWetStreak += 1;
    } else if (r == SoilResponse.tooDry) {
      factor *= 1 - dryStep;
      settledStreak = 0;
      tooWetStreak = 0;
      lastWateredAt = now;
    } else {
      settledStreak += 1;
      tooWetStreak = 0;
      lastWateredAt = now;
    }

    factor = factor.clamp(lo, hi);
    final settleAt = isUser ? 2 : 3;

    return p.copyWith(
      factor: factor,
      settledStreak: settledStreak,
      tooWetStreak: tooWetStreak,
      isSettled: settledStreak >= settleAt,
      eventCount: p.eventCount + 1,
      lastWateredAt: lastWateredAt,
      // 응답 종류와 무관하게 갱신한다. minSnooze 의 기준점이다.
      lastRespondedAt: now,
      updatedAt: now,
    );
  }

  /// 알림 없이 직접 물을 준 경우.
  ///
  /// 예정일보다 2일 이상 일찍 줬다면 "예정보다 빨리 필요했다"는 뜻이므로
  /// 버튼을 추가하지 않고도 얻는 공짜 단축 신호다.
  ///
  /// ⚠️ **단 등록 당일의 물주기는 신호가 아니다.** 주기가 틀렸다는 뜻이
  /// 아니라 시작점을 잡는 행동이기 때문이다. 등록하자마자 물을 주는 건
  /// 자연스러운 흐름인데, 이걸 단축 신호로 읽으면 기준 주기가 아직 한 번도
  /// 검증되기 전에 factor 가 깎여 나간다 (10일 → 7일).
  ///
  /// 이 경우 기준 주기는 그대로 두고 시계만 오늘부터 돌기 시작한다.
  static Plant applyManualWatering(
    Plant p,
    DateTime now, {
    required Climate climate,
    required bool winterModeEnabled,
  }) {
    final today = dateOnly(now);
    final isRegistrationDay = today == dateOnly(p.createdAt);

    if (!isRegistrationDay) {
      final due = nextNotifyDate(
        p,
        now,
        climate: climate,
        winterModeEnabled: winterModeEnabled,
      );
      if (due.difference(today).inDays >= 2) {
        return applyResponse(p, SoilResponse.tooDry, now);
      }
    }

    return p.copyWith(
      lastWateredAt: now,
      lastRespondedAt: now,
      tooWetStreak: 0,
      updatedAt: now,
    );
  }

  /// 배수 문제를 의심해야 하는 상태인가.
  ///
  /// "축축했어요"가 3회 연속이고 factor 가 상한에 닿았다면 주기 문제가
  /// 아니다. 화분 배수구가 막혔거나 받침에 물이 고여 있을 가능성이 높다.
  static bool suspectsDrainageIssue(Plant p) {
    final hi = p.anchorSource == AnchorSource.user ? 1.35 : 1.60;
    return p.tooWetStreak >= 3 && p.factor >= hi - 1e-9;
  }

  /// 계절이 바뀌었을 때 정착을 해제한다.
  /// anchor 는 그대로 두고 factor 도 유지한다 — 개인차는 계절과 무관하다.
  static Plant resetSettlingForSeasonChange(Plant p, DateTime now) =>
      p.copyWith(
        isSettled: false,
        settledStreak: 0,
        updatedAt: now,
      );

  /// 위치를 바꾼 경우. anchor 만 다시 계산하고 학습값은 유지한다.
  static Plant relocate(Plant p, LightLevel light, DateTime now) =>
      reclassify(p, light: light, now: now);

  /// 종류·위치를 바꾼 경우. anchor 만 다시 계산하고 학습값(factor)은 유지한다.
  ///
  /// factor 는 개인차(난방·화분 재질·물 주는 양)를 담고 있고 그건 화분을
  /// 창가로 옮긴다고 달라지지 않는다. 대신 정착은 풀어서, 새 자리에서
  /// 주기가 맞는지 한 번 더 물어보고 확인한다.
  ///
  /// 직접 주기를 입력한 식물은 anchor 를 건드리지 않는다. 사용자가 정한
  /// 값을 테이블 값으로 덮어쓰는 것은 입력을 무시하는 셈이기 때문이다.
  static Plant reclassify(
    Plant p, {
    PlantKind? kind,
    LightLevel? light,
    required DateTime now,
  }) {
    final newKind = kind ?? p.kind;
    final newLight = light ?? p.light;
    final fromTable = p.anchorSource == AnchorSource.table;

    return p.copyWith(
      kind: newKind,
      light: newLight,
      anchorDays: fromTable ? baselineDays(newKind, newLight) : p.anchorDays,
      // 테이블 값은 평시 기준이다.
      anchorInWinter: fromTable ? false : p.anchorInWinter,
      isSettled: false,
      settledStreak: 0,
      updatedAt: now,
    );
  }

  /// 사용자가 주기를 직접 지정한 경우 (수정 화면의 주기 스테퍼).
  ///
  /// ⚠️ factor 를 1.0 으로 되돌린다. 그러지 않으면 "10일"로 고쳤는데
  /// 학습된 factor 0.7 이 곱해져 실제로는 7일에 알림이 가고, 사용자는
  /// 자기가 입력한 값이 무시당했다고 느낀다. 지정한 주기가 곧 다음 주기여야
  /// 한다. 같은 이유로 [Plant.anchorInWinter] 를 지금 계절에 맞춰 둔다 —
  /// 그래야 seasonAdjust 가 1.0 이 되어 입력값이 그대로 쓰인다.
  ///
  /// 학습을 버리는 셈이지만, 방금 사용자가 그 학습 결과를 직접 덮어썼다.
  static Plant setUserInterval(
    Plant p,
    double days, {
    required bool isWinterNow,
    required DateTime now,
  }) =>
      p.copyWith(
        anchorDays: days,
        anchorSource: AnchorSource.user,
        anchorInWinter: isWinterNow,
        factor: 1.0,
        isSettled: false,
        settledStreak: 0,
        updatedAt: now,
      );

  /// 수정 화면의 저장 규칙. 바뀐 항목만 골라 각각 알맞은 변환을 태운다.
  ///
  /// 이름·사진은 주기와 무관하므로 그냥 덮어쓴다. 종류·위치는 실제로 달라진
  /// 경우에만 [reclassify] 를 거친다 — 매번 태우면 **이름만 고쳐도 정착이
  /// 풀린다.** 주기는 사용자가 스테퍼를 실제로 누른 경우에만
  /// [userIntervalDays] 로 들어온다. 화면에 보이던 숫자를 그대로 되돌려
  /// 받아 매번 [setUserInterval] 을 태우면 학습된 factor 가 통째로 날아간다.
  ///
  /// 순서가 중요하다. [reclassify] 가 먼저 anchor 를 다시 잡고, 사용자가
  /// 주기까지 직접 정했다면 그 값이 마지막에 덮어쓴다 — 사람이 명시한 값이
  /// 테이블 값을 이긴다.
  static Plant applyEdit(
    Plant p, {
    required String name,
    required PlantKind kind,
    required LightLevel light,
    double? userIntervalDays,
    String? photoPath,
    bool clearPhoto = false,
    required bool isWinterNow,
    required DateTime now,
  }) {
    var updated = p;

    if (kind != p.kind || light != p.light) {
      updated = reclassify(updated, kind: kind, light: light, now: now);
    }

    if (userIntervalDays != null) {
      updated = setUserInterval(
        updated,
        userIntervalDays,
        isWinterNow: isWinterNow,
        now: now,
      );
    }

    return updated.copyWith(
      name: name,
      photoPath: photoPath,
      clearPhotoPath: clearPhoto,
      updatedAt: now,
    );
  }

  /// 시각을 버리고 날짜만 남긴다.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
