import 'package:flutter_test/flutter_test.dart';
import 'package:ipkong/domain/models/enums.dart';
import 'package:ipkong/domain/models/plant.dart';
import 'package:ipkong/domain/watering_schedule.dart';

/// 2026-12-01. 북반구 겨울.
final d0 = DateTime(2026, 12, 1);

Plant makePlant({
  double anchorDays = WateringSchedule.defaultAnchorDays,
  AnchorSource anchorSource = AnchorSource.table,
  bool anchorInWinter = false,
  PlantKind kind = PlantKind.normal,
  LightLevel light = LightLevel.medium,
  String? photoPath,
  DateTime? createdAt,
}) {
  final ts = createdAt ?? d0;
  return Plant(
    id: 'test',
    name: '몬스테라',
    photoPath: photoPath,
    kind: kind,
    light: light,
    anchorDays: anchorDays,
    anchorSource: anchorSource,
    anchorInWinter: anchorInWinter,
    createdAt: ts,
    updatedAt: ts,
  );
}

int intervalOf(Plant p, DateTime now, {Climate climate = Climate.northern}) =>
    WateringSchedule.nextInterval(
      p,
      now,
      climate: climate,
      winterModeEnabled: true,
    );

DateTime dueOf(Plant p, DateTime now, {Climate climate = Climate.northern}) =>
    WateringSchedule.nextNotifyDate(
      p,
      now,
      climate: climate,
      winterModeEnabled: true,
    );

Plant waterNow(Plant p, DateTime now, {Climate climate = Climate.northern}) =>
    WateringSchedule.applyManualWatering(
      p,
      now,
      climate: climate,
      winterModeEnabled: true,
    );

void main() {
  group('기준 주기 테이블', () {
    test('무정보 기본값은 10일 (7일이 아니다)', () {
      // 리스크가 비대칭이다. 과습은 회복 불가, 과건조는 회복 가능.
      expect(WateringSchedule.defaultAnchorDays, 10.0);
      expect(
        WateringSchedule.baselineDays(PlantKind.normal, LightLevel.medium),
        10.0,
      );
    });

    test('다육과 잎 얇은 식물은 5배 이상 차이난다', () {
      final succulent =
          WateringSchedule.baselineDays(PlantKind.succulent, LightLevel.low);
      final thin =
          WateringSchedule.baselineDays(PlantKind.thinLeaf, LightLevel.bright);
      expect(succulent / thin, greaterThanOrEqualTo(5.0));
    });
  });

  group('계절 보정 — 이중 적용 방지', () {
    test('평시에 정한 anchor 는 겨울에 1.4배가 된다', () {
      final p = makePlant(anchorInWinter: false);
      expect(intervalOf(p, d0), 14); // 10 × 1.4
    });

    test('겨울에 입력한 값은 그 겨울 동안 그대로다', () {
      // 사용자가 겨울에 "14일"이라고 입력했다면 이미 겨울을 고려한 값이다.
      // 여기에 또 1.4를 곱하면 이중 적용이 된다.
      final p = makePlant(
        anchorDays: 14,
        anchorSource: AnchorSource.user,
        anchorInWinter: true,
      );
      expect(intervalOf(p, d0), 14);
    });

    test('겨울에 입력한 값은 여름이 되면 줄어든다', () {
      final p = makePlant(
        anchorDays: 14,
        anchorSource: AnchorSource.user,
        anchorInWinter: true,
      );
      final summer = DateTime(2027, 7, 1);
      expect(intervalOf(p, summer), 10); // 14 / 1.4
    });

    test('다육은 겨울 배율이 1.9다', () {
      final p = makePlant(kind: PlantKind.succulent, anchorDays: 18);
      expect(intervalOf(p, d0), 34); // 18 × 1.9 = 34.2
    });

    test('열대에는 겨울이 없다', () {
      final p = makePlant();
      expect(intervalOf(p, d0, climate: Climate.tropical), 10);
    });

    test('남반구는 12월이 여름이다', () {
      final p = makePlant();
      expect(intervalOf(p, d0, climate: Climate.southern), 10);
      // 남반구의 겨울은 7월이다
      expect(intervalOf(p, DateTime(2027, 7, 1), climate: Climate.southern), 14);
    });
  });

  group('★ 명세서 §5.4 시나리오 — 겨울, 주기 미입력', () {
    test('D0 등록 → D14 첫 알림 → 축축 → D18 (12일 뒤가 아니라 4일 뒤)', () {
      var p = makePlant();

      // D0: interval = 10 × 1.4 × 1.0 = 14
      expect(intervalOf(p, d0), 14);
      expect(dueOf(p, d0), d0.add(const Duration(days: 14)));

      // D14: "축축했어요"
      final d14 = d0.add(const Duration(days: 14));
      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d14);

      // factor 1.0 → 1.3, interval = 10 × 1.4 × 1.3 = 18.2 → 18
      expect(p.factor, closeTo(1.3, 1e-9));
      expect(intervalOf(p, d14), 18);

      // 물을 준 게 아니므로 기산점은 여전히 D0
      expect(p.lastWateredAt, isNull);
      expect(p.scheduleBase, d0);

      // 다음 알림 = D0 + 18 = D18 → 4일 뒤
      final due = dueOf(p, d14);
      expect(due, d0.add(const Duration(days: 18)));
      expect(due.difference(d14).inDays, 4);
    });

    test('D18 축축 → D22, D22 적당 → D44', () {
      var p = makePlant();
      final d14 = d0.add(const Duration(days: 14));
      final d18 = d0.add(const Duration(days: 18));
      final d22 = d0.add(const Duration(days: 22));

      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d14);
      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d18);

      // factor 1.3 × 1.3 = 1.69 → 상한 1.60 으로 clamp
      expect(p.factor, closeTo(1.60, 1e-9));
      expect(intervalOf(p, d18), 22); // 10 × 1.4 × 1.6 = 22.4
      expect(dueOf(p, d18), d22);

      // D22: "적당했어요" → 물을 줬으므로 기산점이 갱신된다
      p = WateringSchedule.applyResponse(p, SoilResponse.justRight, d22);
      expect(p.lastWateredAt, d22);
      expect(dueOf(p, d22), d22.add(const Duration(days: 22)));
    });

    test('축축 응답을 반복해도 알림이 무한정 밀리지 않는다', () {
      // now + interval 로 잘못 구현하면 매번 시계가 리셋되어 발산한다.
      var p = makePlant();
      var now = d0;

      for (var i = 0; i < 6; i++) {
        final due = dueOf(p, now);
        expect(
          due.difference(now).inDays,
          lessThanOrEqualTo(22),
          reason: '$i번째 응답 후 간격이 비정상적으로 벌어졌다',
        );
        now = due;
        p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, now);
      }

      // factor 는 상한에서 멈춘다
      expect(p.factor, lessThanOrEqualTo(1.60 + 1e-9));
    });
  });

  group('minSnooze — 최소 재확인 간격', () {
    test('연장 폭이 작아도 다음 알림이 내일이 되지 않는다', () {
      // 사용자 입력(±10%) + 정착 직전 상황
      var p = makePlant(
        anchorDays: 10,
        anchorSource: AnchorSource.user,
        anchorInWinter: true, // 겨울 배율을 배제해 순수 계산으로
      );
      final d10 = d0.add(const Duration(days: 10));

      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d10);
      expect(intervalOf(p, d10), 11); // 10 × 1.1

      // 기산점 + 11 = D11 은 내일이지만, minSnooze(=2) 가 하한을 만든다
      final due = dueOf(p, d10);
      expect(due.difference(d10).inDays, greaterThanOrEqualTo(2));
    });
  });

  group('학습 강도', () {
    test('사용자 입력이 있으면 factor 범위가 좁다', () {
      var p = makePlant(
        anchorSource: AnchorSource.user,
        anchorInWinter: true,
      );
      for (var i = 0; i < 20; i++) {
        p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d0);
      }
      expect(p.factor, closeTo(1.35, 1e-9));
    });

    test('입력이 없으면 범위가 넓고 초기 스텝이 크다', () {
      var p = makePlant();
      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d0);
      expect(p.factor, closeTo(1.30, 1e-9)); // 초기 스텝 30%

      for (var i = 0; i < 20; i++) {
        p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d0);
      }
      expect(p.factor, closeTo(1.60, 1e-9));
    });

    test('단축이 연장보다 크지만 초기에 하한을 곧장 포화시키지 않는다', () {
      var p = makePlant();
      p = WateringSchedule.applyResponse(p, SoilResponse.tooDry, d0);
      // dryStep = min(0.30 × 1.5, 0.35) = 0.35 → 1.0 × 0.65
      expect(p.factor, closeTo(0.65, 1e-9));
      expect(p.factor, greaterThan(0.60)); // 하한에 닿지 않았다
    });

    test('바짝 말랐어요는 물을 준 것으로 처리된다', () {
      final p = WateringSchedule.applyResponse(
        makePlant(),
        SoilResponse.tooDry,
        d0,
      );
      expect(p.lastWateredAt, d0);
    });
  });

  group('정착', () {
    test('입력 없으면 적당 3회, 입력 있으면 2회에 정착한다', () {
      var table = makePlant();
      for (var i = 0; i < 2; i++) {
        table = WateringSchedule.applyResponse(
          table,
          SoilResponse.justRight,
          d0,
        );
      }
      expect(table.isSettled, isFalse);
      table =
          WateringSchedule.applyResponse(table, SoilResponse.justRight, d0);
      expect(table.isSettled, isTrue);

      var user = makePlant(anchorSource: AnchorSource.user);
      user = WateringSchedule.applyResponse(user, SoilResponse.justRight, d0);
      expect(user.isSettled, isFalse);
      user = WateringSchedule.applyResponse(user, SoilResponse.justRight, d0);
      expect(user.isSettled, isTrue);
    });

    test('축축 응답 하나로 연속 기록이 끊긴다', () {
      var p = makePlant();
      p = WateringSchedule.applyResponse(p, SoilResponse.justRight, d0);
      p = WateringSchedule.applyResponse(p, SoilResponse.justRight, d0);
      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d0);
      expect(p.settledStreak, 0);
      expect(p.isSettled, isFalse);
    });

    test('계절이 바뀌면 정착이 풀리고 factor 는 유지된다', () {
      var p = makePlant();
      for (var i = 0; i < 3; i++) {
        p = WateringSchedule.applyResponse(p, SoilResponse.justRight, d0);
      }
      final before = p.factor;
      p = WateringSchedule.resetSettlingForSeasonChange(p, d0);
      expect(p.isSettled, isFalse);
      expect(p.factor, before);
    });
  });

  group('배수 문제 감지', () {
    test('축축 3연속 + factor 상한이면 배수를 의심한다', () {
      var p = makePlant();
      expect(WateringSchedule.suspectsDrainageIssue(p), isFalse);
      for (var i = 0; i < 3; i++) {
        p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d0);
      }
      expect(p.tooWetStreak, 3);
      expect(WateringSchedule.suspectsDrainageIssue(p), isTrue);
    });

    test('물을 준 응답이 오면 연속 기록이 초기화된다', () {
      var p = makePlant();
      for (var i = 0; i < 3; i++) {
        p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d0);
      }
      p = WateringSchedule.applyResponse(p, SoilResponse.justRight, d0);
      expect(p.tooWetStreak, 0);
      expect(WateringSchedule.suspectsDrainageIssue(p), isFalse);
    });
  });

  group('위치 변경', () {
    test('anchor 는 다시 계산되고 학습값은 남는다', () {
      var p = makePlant();
      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d0);
      final learned = p.factor;

      p = WateringSchedule.relocate(p, LightLevel.bright, d0);
      expect(p.anchorDays, 7.0); // normal × bright
      expect(p.factor, learned); // 개인차는 계절·위치와 무관하다
      expect(p.isSettled, isFalse);
    });

    test('사용자가 입력한 주기는 위치를 바꿔도 유지된다', () {
      var p = makePlant(anchorDays: 5, anchorSource: AnchorSource.user);
      p = WateringSchedule.relocate(p, LightLevel.low, d0);
      expect(p.anchorDays, 5.0);
    });

    test('종류를 바꾸면 anchor 가 새 종류 기준으로 다시 계산된다', () {
      var p = makePlant(); // normal × medium = 10
      p = WateringSchedule.reclassify(p, kind: PlantKind.succulent, now: d0);
      expect(p.anchorDays, 18.0); // succulent × medium
      expect(p.light, LightLevel.medium); // 넘기지 않은 값은 그대로
    });

    test('종류와 위치를 함께 바꿔도 한 번에 반영된다', () {
      var p = makePlant();
      p = WateringSchedule.reclassify(
        p,
        kind: PlantKind.thinLeaf,
        light: LightLevel.bright,
        now: d0,
      );
      expect(p.anchorDays, 4.0); // thinLeaf × bright
    });
  });

  group('수정 화면의 주기 지정', () {
    // 화면에 "12일"이라 적어두고 저장했더니 학습된 factor 가 곱해져 8일에
    // 알림이 가면, 사용자는 입력이 무시당했다고 느낀다.
    test('지정한 값이 곧 다음 주기가 된다', () {
      var p = makePlant();
      p = WateringSchedule.applyResponse(p, SoilResponse.tooDry, d0);
      expect(p.factor, lessThan(1.0)); // 학습이 붙은 상태

      p = WateringSchedule.setUserInterval(p, 12, isWinterNow: true, now: d0);
      expect(intervalOf(p, d0), 12); // d0 는 북반구 겨울이다
    });

    test('평시에 지정한 값도 그대로 적용된다', () {
      final summer = DateTime(2026, 7, 1);
      var p = makePlant(createdAt: summer);
      p = WateringSchedule.setUserInterval(p, 9, isWinterNow: false, now: summer);
      expect(intervalOf(p, summer), 9);
    });

    test('지정하면 anchorSource 가 user 로 바뀌고 정착이 풀린다', () {
      var p = makePlant();
      p = WateringSchedule.applyResponse(p, SoilResponse.justRight, d0);
      p = WateringSchedule.applyResponse(p, SoilResponse.justRight, d0);
      p = WateringSchedule.applyResponse(p, SoilResponse.justRight, d0);
      expect(p.isSettled, isTrue);

      p = WateringSchedule.setUserInterval(p, 12, isWinterNow: true, now: d0);
      expect(p.anchorSource, AnchorSource.user);
      expect(p.isSettled, isFalse);
      expect(p.settledStreak, 0);
    });
  });

  test('주기는 2~60일로 제한된다', () {
    final tiny = makePlant(anchorDays: 1, anchorInWinter: true);
    expect(intervalOf(tiny, d0), greaterThanOrEqualTo(2));

    final huge = makePlant(anchorDays: 100, anchorInWinter: true);
    expect(intervalOf(huge, d0), lessThanOrEqualTo(60));
  });

  group('minSnooze 하한의 기준점 (회귀)', () {
    test('밀린 식물의 예정일은 조회 시점과 무관하게 고정된다', () {
      // floor 를 now 에 묶으면 조회할 때마다 "지금부터 2일 뒤"로 밀려서
      // 알림이 영영 오지 않는다. 실제로 잡힌 버그다.
      final p = makePlant(
        anchorDays: 5,
        anchorInWinter: true,
        createdAt: d0.subtract(const Duration(days: 90)),
      );

      final asked1 = dueOf(p, d0);
      final asked2 = dueOf(p, d0.add(const Duration(days: 3)));
      final asked3 = dueOf(p, d0.add(const Duration(days: 10)));

      expect(asked1, asked2);
      expect(asked2, asked3);
      expect(asked1.isBefore(d0), isTrue, reason: '이미 지난 예정일이어야 한다');
    });

    test('응답 전에는 하한이 기산점을 기준으로 잡힌다', () {
      final p = makePlant(anchorDays: 10, anchorInWinter: true);
      expect(p.lastRespondedAt, isNull);
      expect(dueOf(p, d0), d0.add(const Duration(days: 10)));
    });

    test('응답하면 하한의 기준점이 그 시각으로 옮겨간다', () {
      var p = makePlant(anchorDays: 10, anchorInWinter: true);
      final d10 = d0.add(const Duration(days: 10));
      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d10);
      expect(p.lastRespondedAt, d10);
      expect(p.lastWateredAt, isNull, reason: '축축했어요는 물을 준 게 아니다');
    });
  });

  group('등록 당일 물주기 (회귀)', () {
    // anchorInWinter: true 로 두면 겨울 배율이 1.0 이 되어 순수 계산이 된다.
    Plant fresh() => makePlant(anchorDays: 10, anchorInWinter: true);

    test('등록 당일 물주기는 주기를 바꾸지 않는다', () {
      final p = fresh();
      expect(intervalOf(p, d0), 10);

      final after = waterNow(p, d0);

      expect(after.factor, 1.0, reason: '시작점을 잡는 행동이지 단축 신호가 아니다');
      expect(intervalOf(after, d0), 10, reason: '10일이 7일로 바뀌면 안 된다');
      expect(after.lastWateredAt, d0);
      expect(dueOf(after, d0), d0.add(const Duration(days: 10)));
    });

    test('등록 당일 여러 번 눌러도 주기가 깎이지 않는다', () {
      var p = fresh();
      for (var i = 0; i < 3; i++) {
        p = waterNow(p, d0);
      }
      expect(p.factor, 1.0);
      expect(intervalOf(p, d0), 10);
    });

    test('등록 이튿날부터는 조기 물주기가 단축 신호로 남는다', () {
      final d1 = d0.add(const Duration(days: 1));
      final after = waterNow(fresh(), d1);

      expect(after.factor, lessThan(1.0), reason: '예정일보다 한참 이르면 신호가 맞다');
      expect(after.lastWateredAt, d1);
    });

    test('예정일에 가까운 물주기는 등록일과 무관하게 신호가 아니다', () {
      // 예정일 D10 · D9 에 물주기 → 차이 1일 < 2일
      final d9 = d0.add(const Duration(days: 9));
      final after = waterNow(fresh(), d9);

      expect(after.factor, 1.0);
      expect(after.lastWateredAt, d9);
    });

    test('등록 당일 물주기 후에도 알림 응답 학습은 정상 동작한다', () {
      var p = waterNow(fresh(), d0);
      final d10 = d0.add(const Duration(days: 10));

      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d10);
      expect(p.factor, closeTo(1.30, 1e-9), reason: '첫 응답이므로 초기 스텝 30%');
    });
  });

  group('수정 화면 저장 (applyEdit)', () {
    /// 학습이 얹힌 상태의 식물. 수정이 이걸 날리는지 보는 게 핵심이다.
    Plant learned() {
      var p = makePlant(photoPath: '/tmp/before.jpg');
      p = WateringSchedule.applyResponse(p, SoilResponse.tooWet, d0);
      return p;
    }

    Plant edit(
      Plant p, {
      String name = '몬스테라',
      PlantKind? kind,
      LightLevel? light,
      double? userIntervalDays,
      String? photoPath,
      bool clearPhoto = false,
    }) =>
        WateringSchedule.applyEdit(
          p,
          name: name,
          kind: kind ?? p.kind,
          light: light ?? p.light,
          userIntervalDays: userIntervalDays,
          photoPath: photoPath ?? p.photoPath,
          clearPhoto: clearPhoto,
          isWinterNow: true, // d0 는 북반구 겨울
          now: d0,
        );

    // 이 테스트가 이 그룹의 존재 이유다. 이름만 고치러 들어온 사람의
    // 학습값을 날리면 그 식물은 처음부터 다시 배워야 한다.
    test('이름만 바꾸면 학습값도 정착도 그대로다', () {
      final before = learned();
      final after = edit(before, name: '새 이름');

      expect(after.name, '새 이름');
      expect(after.factor, before.factor);
      expect(after.anchorDays, before.anchorDays);
      expect(after.anchorSource, before.anchorSource);
      expect(after.settledStreak, before.settledStreak);
      expect(after.photoPath, '/tmp/before.jpg');
    });

    test('사진만 바꿔도 주기는 건드리지 않는다', () {
      final before = learned();
      final after = edit(before, photoPath: '/tmp/after.jpg');

      expect(after.photoPath, '/tmp/after.jpg');
      expect(after.factor, before.factor);
    });

    test('사진 지우기가 반영된다', () {
      final after = edit(learned(), clearPhoto: true);
      expect(after.photoPath, isNull);
    });

    test('위치를 바꾸면 anchor 가 다시 잡히고 학습값은 남는다', () {
      final before = learned();
      final after = edit(before, light: LightLevel.bright);

      expect(after.light, LightLevel.bright);
      expect(after.anchorDays, 7.0); // normal × bright
      expect(after.factor, before.factor, reason: '개인차는 자리와 무관하다');
      expect(after.isSettled, isFalse);
    });

    test('주기를 직접 지정하면 그 값이 곧 다음 주기가 된다', () {
      final after = edit(learned(), userIntervalDays: 12);

      expect(after.anchorSource, AnchorSource.user);
      expect(intervalOf(after, d0), 12);
    });

    // 순서 회귀: reclassify 가 anchor 를 테이블 값으로 되돌린 뒤에
    // setUserInterval 이 덮어써야 한다. 순서가 뒤집히면 사용자가 고른
    // 숫자가 테이블 값에 먹힌다.
    test('위치와 주기를 함께 바꾸면 직접 정한 주기가 이긴다', () {
      final after = edit(
        learned(),
        light: LightLevel.low,
        userIntervalDays: 9,
      );

      expect(after.light, LightLevel.low);
      expect(after.anchorDays, 9.0, reason: '테이블 값 14일이 아니라 지정값');
      expect(intervalOf(after, d0), 9);
    });

    test('바뀐 게 없으면 updatedAt 외에는 그대로다', () {
      final before = learned();
      final after = edit(before);

      expect(after.factor, before.factor);
      expect(after.light, before.light);
      expect(after.kind, before.kind);
      expect(after.anchorDays, before.anchorDays);
      expect(after.tooWetStreak, before.tooWetStreak);
    });
  });
}
