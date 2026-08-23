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
import 'package:ipkong/ui/onboarding_screen.dart';
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
}
