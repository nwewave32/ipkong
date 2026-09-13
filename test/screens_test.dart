import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipkong/domain/models/enums.dart';
import 'package:ipkong/domain/models/plant.dart';
import 'package:ipkong/l10n/app_localizations.dart';
import 'package:ipkong/providers/providers.dart';
import 'package:ipkong/ui/edit_plant_screen.dart';
import 'package:ipkong/ui/notify_time_sheet.dart';
import 'package:ipkong/ui/onboarding_screen.dart';
import 'package:ipkong/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 화면 렌더링 테스트.
///
/// DB 를 타지 않는 지점만 본다 — sqflite 는 순수 Dart 테스트에서 열리지
/// 않으므로 저장 동작은 도메인 단위 테스트(`watering_schedule_test.dart`)가
/// 대신 지킨다. 여기서 잡고 싶은 건 "레이아웃이 터지지 않는가"와
/// "화면에 보이는 숫자가 계산 결과와 같은가" 두 가지다.
///
/// [AppStringsDelegate.load] 가 Future 라 첫 프레임에는 아직 문자열이 없다.
/// pump 한 번으로 끝내면 빈 화면을 검사하게 되므로 반드시 settle 시킨다.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('ko'),
  List<Override> overrides = const [],
}) async {
  // 기본 800×600 뷰포트에서는 폼 아래쪽(위치 3택·주기 스테퍼)이 ListView
  // 밖이라 아예 빌드되지 않는다. 화면 전체를 한 번에 보도록 늘려 둔다.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    await harness(child, locale: locale, overrides: overrides),
  );
  await tester.pumpAndSettle();
}

Future<Widget> harness(
  Widget child, {
  Locale locale = const Locale('ko'),
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      climateProvider.overrideWithValue(Climate.northern),
      ...overrides,
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

Plant plant({
  double anchorDays = 10,
  AnchorSource anchorSource = AnchorSource.table,
  double factor = 1.0,
  bool anchorInWinter = false,
  PlantKind kind = PlantKind.normal,
  LightLevel light = LightLevel.medium,
}) {
  final ts = DateTime(2026, 7, 1); // 북반구 여름 — 겨울 배율이 끼지 않는다
  return Plant(
    id: 'p1',
    name: '몬스테라',
    kind: kind,
    light: light,
    anchorDays: anchorDays,
    anchorSource: anchorSource,
    anchorInWinter: anchorInWinter,
    factor: factor,
    createdAt: ts,
    updatedAt: ts,
  );
}

void main() {
  group('온보딩', () {
    testWidgets('3화면을 넘기면 마지막에 시작 버튼이 나온다', (tester) async {
      await pumpScreen(tester, const OnboardingScreen());
      final s = const AppStrings(Locale('ko'));

      expect(find.text(s.onboard1Title), findsOneWidget);
      expect(find.text(s.onboardNext), findsOneWidget);

      await tester.tap(find.text(s.onboardNext));
      await tester.pumpAndSettle();
      expect(find.text(s.onboard2Title), findsOneWidget);

      await tester.tap(find.text(s.onboardNext));
      await tester.pumpAndSettle();
      expect(find.text(s.onboard3Title), findsOneWidget);
      expect(find.text(s.onboardStart), findsOneWidget);

      // §10.1 — 마지막 화면에 돌봄 링크 티저 한 줄.
      expect(find.textContaining(s.careLinkTitle), findsOneWidget);
    });

    testWidgets('건너뛰기는 온보딩을 끝내되 식물 추가로 이어지지 않는다', (tester) async {
      late WidgetRef captured;
      await pumpScreen(
        tester,
        Consumer(
          builder: (_, ref, _) {
            captured = ref;
            return const OnboardingScreen();
          },
        ),
      );

      await tester.tap(find.text(const AppStrings(Locale('ko')).skip));
      await tester.pumpAndSettle();

      expect(captured.read(onboardingDoneProvider), isTrue);
      expect(captured.read(startAddPlantProvider), isFalse);
    });

    testWidgets('끝까지 보면 식물 추가로 이어진다', (tester) async {
      late WidgetRef captured;
      await pumpScreen(
        tester,
        Consumer(
          builder: (_, ref, _) {
            captured = ref;
            return const OnboardingScreen();
          },
        ),
      );
      final s = const AppStrings(Locale('ko'));

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text(s.onboardNext));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(s.onboardStart));
      await tester.pumpAndSettle();

      expect(captured.read(onboardingDoneProvider), isTrue);
      expect(captured.read(startAddPlantProvider), isTrue);
    });

    testWidgets('영어에서도 잘리지 않는다', (tester) async {
      await pumpScreen(tester, const OnboardingScreen(),
          locale: const Locale('en'));
      expect(tester.takeException(), isNull);
      expect(
        find.text(const AppStrings(Locale('en')).onboard1Title),
        findsOneWidget,
      );
    });
  });

  group('식물 수정', () {
    testWidgets('기존 값이 채워진 채로 열린다', (tester) async {
      await pumpScreen(
        tester,
        EditPlantScreen(plant: plant(light: LightLevel.bright)),
      );

      expect(find.text('몬스테라'), findsOneWidget);
      // 선택된 항목에만 체크가 붙는다 (종류 1 + 위치 1).
      expect(find.byIcon(Icons.check), findsNWidgets(2));
    });

    testWidgets('스테퍼는 anchor 가 아니라 지금 적용 중인 주기를 보여준다', (tester) async {
      // anchor 10일 × factor 1.3 = 13일. 상세 화면이 보여주는 값과 같아야 한다.
      await pumpScreen(tester, EditPlantScreen(plant: plant(factor: 1.3)));
      expect(find.text('13일'), findsOneWidget);
    });

    testWidgets('위치를 바꾸면 제안 주기가 따라 움직인다', (tester) async {
      await pumpScreen(tester, EditPlantScreen(plant: plant()));
      final s = const AppStrings(Locale('ko'));

      expect(find.text('10일'), findsOneWidget); // normal × medium

      await tester.tap(find.text(s.lightLow));
      await tester.pumpAndSettle();
      expect(find.text('14일'), findsOneWidget); // normal × low
    });

    testWidgets('직접 입력한 주기는 위치를 바꿔도 유지된다', (tester) async {
      await pumpScreen(
        tester,
        EditPlantScreen(
          plant: plant(anchorDays: 5, anchorSource: AnchorSource.user),
        ),
      );
      final s = const AppStrings(Locale('ko'));

      await tester.tap(find.text(s.lightLow));
      await tester.pumpAndSettle();
      expect(find.text('5일'), findsOneWidget);
    });

    testWidgets('스테퍼를 누르면 덮어쓰기 안내가 뜬다', (tester) async {
      await pumpScreen(tester, EditPlantScreen(plant: plant()));
      final s = const AppStrings(Locale('ko'));

      expect(find.text(s.intervalOverrideWarning), findsNothing);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('11일'), findsOneWidget);
      expect(find.text(s.intervalOverrideWarning), findsOneWidget);
      expect(find.text(s.intervalUserNote), findsOneWidget);
    });

    // 선택을 색과 체크 아이콘으로만 표시하면 스크린 리더 사용자는 지금
    // 무엇이 골라져 있는지 알 수 없다.
    testWidgets('선택된 항목이 스크린 리더에 "선택됨"으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(
        tester,
        EditPlantScreen(plant: plant(light: LightLevel.bright)),
      );
      final s = const AppStrings(Locale('ko'));

      SemanticsNode nodeOf(String label) =>
          tester.getSemantics(find.text(label));

      expect(nodeOf(s.lightBright), isSemantics(isSelected: true));
      expect(nodeOf(s.lightMedium), isSemantics(isSelected: false));
      expect(nodeOf(s.lightLow), isSemantics(isSelected: false));

      await tester.tap(find.text(s.lightLow));
      await tester.pumpAndSettle();

      expect(nodeOf(s.lightBright), isSemantics(isSelected: false));
      expect(nodeOf(s.lightLow), isSemantics(isSelected: true));

      handle.dispose();
    });

    testWidgets('사진 영역이 버튼으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, EditPlantScreen(plant: plant()));
      final s = const AppStrings(Locale('ko'));

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('${s.photo}, ${s.photoOptional}'),
        ),
        isSemantics(isButton: true, hasTapAction: true),
      );

      handle.dispose();
    });

    testWidgets('정착된 식물의 자리를 옮기면 정착 해제를 미리 알린다', (tester) async {
      final settled = plant().copyWith(isSettled: true, settledStreak: 3);
      await pumpScreen(tester, EditPlantScreen(plant: settled));
      final s = const AppStrings(Locale('ko'));

      expect(find.text(s.relocateResetsSettling), findsNothing);

      await tester.tap(find.text(s.lightBright));
      await tester.pumpAndSettle();

      expect(find.text(s.relocateResetsSettling), findsOneWidget);
    });
  });

  group('설정 — 알림 시간', () {
    testWidgets('현재 시각이 알약에 보인다', (tester) async {
      await pumpScreen(tester, const SettingsScreen());

      // 기본값 09:00. 로케일·12h/24h 설정에 따라 표기가 달라지므로
      // 형식이 아니라 시각이 보이는지만 본다.
      expect(find.textContaining('9:00'), findsWidgets);

      // 고르는 일은 전부 바텀시트가 맡는다. 행에는 선택지가 없어야 한다.
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('시각이 바뀌면 화면이 곧바로 따라간다', (tester) async {
      // SettingsRepository 는 값이 바뀌어도 Riverpod 에 알리지 않는다.
      // 저장소를 직접 watch 하면 저장은 되는데 화면이 옛 값을 계속 보여준다.
      await pumpScreen(tester, const SettingsScreen());
      expect(find.textContaining('9:00'), findsWidgets);

      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)))
          .read(notifyTimeProvider.notifier)
          .state = const TimeOfDay(hour: 19, minute: 30);
      await tester.pump();

      expect(find.textContaining('7:30'), findsWidgets);
      expect(find.textContaining('9:00'), findsNothing);
    });

    testWidgets('시각 알약이 무엇을 바꾸는 버튼인지 읽힌다', (tester) async {
      // 눈으로는 알약과 연필이 "누르는 곳"이라고 말해주지만, 화면을 못 보는
      // 사람에게는 "오전 9:00" 이라는 버튼 하나가 있을 뿐이다.
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, const SettingsScreen());

      final s = const AppStrings(Locale('ko'));
      final pill = tester.getSemantics(
        find.bySemanticsLabel(RegExp(RegExp.escape(s.notifyTimeChange))),
      );

      expect(pill, isSemantics(isButton: true, hasTapAction: true));

      // 알약이 자기 노드를 갖는지까지 본다. Semantics(container:) 를 빠뜨리면
      // 주변 텍스트와 한 덩어리로 합쳐져, 제목·설명까지 묶인 거대한 버튼
      // 하나가 읽히고 각 문구를 따로 훑을 수 없게 된다.
      expect(pill.label, startsWith(s.notifyTime));
      expect(pill.label, endsWith(s.notifyTimeChange));
      expect(
        pill.label,
        isNot(contains(s.notifyTimeDesc)),
        reason: '설명까지 알약 버튼에 딸려 들어가면 안 된다',
      );

      handle.dispose();
    });

    testWidgets('영어에서도 잘리지 않는다', (tester) async {
      await pumpScreen(tester, const SettingsScreen(),
          locale: const Locale('en'));
      expect(tester.takeException(), isNull);
      expect(
        find.text(const AppStrings(Locale('en')).notifyTimeDesc),
        findsOneWidget,
      );
    });
  });

  group('알림 시간 바텀시트', () {
    testWidgets('칩을 누르면 그 시각으로 확정된다', (tester) async {
      TimeOfDay? result;
      await pumpScreen(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showNotifyTimeSheet(
                context,
                initial: const TimeOfDay(hour: 9, minute: 0),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 12시간제에서 '오후 7:00' 은 19시다. 여기서 12를 더하고 빼는 걸
      // 틀리면 알림이 12시간 어긋난 채로 나간다.
      await tester.tap(find.text('오후 7:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(result, const TimeOfDay(hour: 19, minute: 0));
    });

    testWidgets('아무것도 건드리지 않으면 열었을 때 값 그대로다', (tester) async {
      TimeOfDay? result;
      await pumpScreen(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showNotifyTimeSheet(
                context,
                initial: const TimeOfDay(hour: 7, minute: 30),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(result, const TimeOfDay(hour: 7, minute: 30));
    });

    testWidgets('닫기는 아무것도 바꾸지 않는다', (tester) async {
      TimeOfDay? result;
      var returned = false;
      await pumpScreen(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showNotifyTimeSheet(
                  context,
                  initial: const TimeOfDay(hour: 9, minute: 0),
                );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('오후 7:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(result, isNull, reason: '칩을 눌러도 확정 전에는 값이 나가면 안 된다');
    });
  });

  group('알림 시간 바텀시트 — 스크린 리더 · 24시간제 · 칩 애니메이션', () {
    const ko = AppStrings(Locale('ko'));

    /// 시트를 열어 두고, 닫혔을 때 돌려받은 값을 꺼내는 함수를 준다.
    Future<TimeOfDay? Function()> openSheet(
      WidgetTester tester,
      TimeOfDay initial,
    ) async {
      TimeOfDay? result;
      await pumpScreen(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result =
                  await showNotifyTimeSheet(context, initial: initial),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    /// 라벨이 **정확히** 같은 노드만 찾는다. '시' 로 찾으면 '알림 시간' 도 걸린다.
    SemanticsFinder wheel(String label) =>
        find.semantics.byLabel(RegExp('^${RegExp.escape(label)}\$'));

    SemanticsData data(String label) =>
        wheel(label).evaluate().single.getSemanticsData();

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
    }

    testWidgets('휠마다 스크린 리더로 한 칸씩 조절할 수 있다', (tester) async {
      // ListWheelScrollView 는 늘리기/줄이기 액션을 주지 않는다. 직접 붙이지
      // 않으면 화면을 못 보는 사람은 칩 세 개 말고는 시각을 고를 수 없다.
      final handle = tester.ensureSemantics();
      final result = await openSheet(tester, const TimeOfDay(hour: 9, minute: 0));

      final hour = data(ko.wheelHour);
      expect(hour.value, '9');
      expect(hour.increasedValue, '10');
      expect(hour.decreasedValue, '8');
      expect(hour.hasAction(SemanticsAction.increase), isTrue);
      expect(hour.hasAction(SemanticsAction.decrease), isTrue);

      tester.semantics.performAction(wheel(ko.wheelHour), SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(data(ko.wheelHour).value, '10');

      await confirm(tester);
      expect(result(), const TimeOfDay(hour: 10, minute: 0));
      handle.dispose();
    });

    testWidgets('분은 00 에서 줄이면 55 로 돈다', (tester) async {
      final handle = tester.ensureSemantics();
      final result = await openSheet(tester, const TimeOfDay(hour: 9, minute: 0));

      expect(data(ko.wheelMinute).decreasedValue, '55');
      tester.semantics.performAction(
        wheel(ko.wheelMinute),
        SemanticsAction.decrease,
      );
      await tester.pumpAndSettle();

      await confirm(tester);
      expect(result(), const TimeOfDay(hour: 9, minute: 55));
      handle.dispose();
    });

    testWidgets('오전·오후는 돌지 않는다 — 끝에서는 그쪽 액션이 없다', (tester) async {
      final handle = tester.ensureSemantics();
      final result = await openSheet(tester, const TimeOfDay(hour: 9, minute: 0));

      final ap = data(ko.wheelAmPm);
      expect(ap.value, '오전');
      expect(ap.hasAction(SemanticsAction.decrease), isFalse);
      expect(ap.hasAction(SemanticsAction.increase), isTrue);

      tester.semantics.performAction(wheel(ko.wheelAmPm), SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(data(ko.wheelAmPm).hasAction(SemanticsAction.increase), isFalse);

      await confirm(tester);
      expect(result(), const TimeOfDay(hour: 21, minute: 0));
      handle.dispose();
    });

    testWidgets('24시간제에서는 오전·오후 칸 없이 두 칸으로 돈다', (tester) async {
      tester.platformDispatcher.alwaysUse24HourFormatTestValue = true;
      addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);

      final result =
          await openSheet(tester, const TimeOfDay(hour: 21, minute: 35));

      expect(find.text('오전'), findsNothing);
      expect(find.text('오후'), findsNothing);
      expect(find.text('21'), findsOneWidget);

      // 아무것도 건드리지 않으면 열었을 때 값 그대로.
      await confirm(tester);
      expect(result(), const TimeOfDay(hour: 21, minute: 35));
    });

    testWidgets('24시간제 칩도 그 시각으로 확정된다', (tester) async {
      tester.platformDispatcher.alwaysUse24HourFormatTestValue = true;
      addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);

      final result = await openSheet(tester, const TimeOfDay(hour: 9, minute: 0));

      await tester.tap(find.text('19:00'));
      await tester.pumpAndSettle();
      await confirm(tester);
      expect(result(), const TimeOfDay(hour: 19, minute: 0));
    });

    testWidgets('칩으로 휠이 굴러가는 도중에 확정해도 칩의 시각이 확정된다', (tester) async {
      // 휠이 굴러가는 동안 지나가는 칸마다 값이 바뀌면, 그 사이에 ✓ 를 누른
      // 사람은 누르지도 않은 중간 시각을 받는다. 오후 1시 → 오전 7시는 여섯 칸을
      // 거꾸로 지나가므로 중간에 멈춰 세우기 좋다.
      final result = await openSheet(tester, const TimeOfDay(hour: 13, minute: 0));

      await tester.tap(find.text('오전 7:00'));
      // 첫 프레임에서 애니메이션 시계가 **시작**하고, 그다음 프레임부터 휠이
      // 움직인다. pump 한 번이면 휠이 한 칸도 안 움직인 채로 확정해 버려서
      // 버그가 있어도 통과한다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await confirm(tester);

      expect(result(), const TimeOfDay(hour: 7, minute: 0));
    });
  });

  group('설정 — 행 정렬', () {
    /// 실제 폰 폭(393pt)에서 잰다. 넓은 테스트 화면에서는 글이 한 줄에 다
    /// 들어가 버려서, 여러 줄일 때만 드러나는 어긋남을 못 잡는다.
    Future<void> pumpPhone(WidgetTester tester) async {
      await pumpScreen(tester, const SettingsScreen());
      tester.view.physicalSize = const Size(393, 2400);
      await tester.pumpAndSettle();
    }

    double cy(WidgetTester tester, Finder f) =>
        tester.getRect(f.first).center.dy;

    testWidgets('아이콘 · 제목 · 컨트롤이 제목 줄 가운데에 선다', (tester) async {
      await pumpPhone(tester);
      final s = const AppStrings(Locale('ko'));

      // (아이콘, 제목, 오른쪽 컨트롤)
      final rows = [
        (Icons.notifications_outlined, s.notifyTime,
            find.byIcon(Icons.edit_outlined)),
        (Icons.ac_unit, s.winterMode, find.byType(Switch)),
        (Icons.ios_share, s.exportData, null),
        (Icons.language, s.language, find.byType(DropdownButton<String?>)),
      ];

      for (final (icon, title, trailing) in rows) {
        final line = cy(tester, find.text(title));
        expect(cy(tester, find.byIcon(icon)), closeTo(line, 0.5),
            reason: '$title: 아이콘이 제목 줄 가운데에서 벗어났다');
        if (trailing != null) {
          expect(cy(tester, trailing), closeTo(line, 0.5),
              reason: '$title: 오른쪽 컨트롤이 제목 줄 가운데에서 벗어났다');
        }
      }
    });

    testWidgets('설명은 컨트롤에 밀리지 않고 오른쪽 끝까지 쓴다', (tester) async {
      // 컨트롤 옆에 끼워 넣으면 폭이 좁아져 한글이 단어 중간에서 끊긴다.
      await pumpPhone(tester);
      final s = const AppStrings(Locale('ko'));

      final pill = tester.getRect(find.byIcon(Icons.edit_outlined));
      final desc = tester.getRect(find.text(s.notifyTimeDesc));
      expect(desc.top, greaterThanOrEqualTo(pill.bottom),
          reason: '설명이 알약 옆이 아니라 아래에 와야 한다');

      final title = tester.getRect(find.text(s.notifyTime));
      expect(desc.left, closeTo(title.left, 0.5),
          reason: '설명은 제목과 같은 시작선에서 시작한다');
    });

    testWidgets('시각 버튼은 배경 없이 설명과 떨어져 있다', (tester) async {
      await pumpPhone(tester);
      final s = const AppStrings(Locale('ko'));
      final scheme =
          Theme.of(tester.element(find.byType(SettingsScreen))).colorScheme;
      final pencil = find.byIcon(Icons.edit_outlined);

      // 채움 배경이 있으면 한 화면에서 그것만 튀어 부담스럽다.
      expect(
        find.ancestor(
          of: pencil,
          matching: find.byWidgetPredicate(
            (w) => w is Material && w.color == scheme.primaryContainer,
          ),
        ),
        findsNothing,
      );

      // 누르는 영역(물결이 퍼지는 사각형)의 아랫선과 설명 윗선 사이에 틈이 있다.
      final button = tester.getRect(
        find.ancestor(of: pencil, matching: find.byType(InkWell)).first,
      );
      final desc = tester.getRect(find.text(s.notifyTimeDesc));
      expect(desc.top - button.bottom, greaterThanOrEqualTo(3.5),
          reason: '시각 버튼이 설명에 붙어 있다');
    });

    testWidgets('행 여백이 위아래로 같다', (tester) async {
      // 12 / 14 처럼 위아래가 다르면 가운데 정렬이 그만큼 한쪽으로 쏠린다.
      await pumpPhone(tester);
      final s = const AppStrings(Locale('ko'));

      final row = find.ancestor(
        of: find.text(s.language),
        matching: find.byWidgetPredicate(
          (w) => w is Padding && w.padding is EdgeInsets &&
              (w.padding as EdgeInsets).left == 16 &&
              (w.padding as EdgeInsets).top > 0,
        ),
      ).first;
      final padding = tester.widget<Padding>(row).padding as EdgeInsets;
      expect(padding.top, padding.bottom);
    });

    testWidgets('폰 폭에서 넘치는 곳이 없다', (tester) async {
      await pumpPhone(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
