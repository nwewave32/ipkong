import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/plant.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'add_plant_screen.dart';
import 'plants_screen.dart';
import 'settings_screen.dart';
import 'soil_answer.dart';
import 'today_screen.dart';
import 'winter_prompt.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  /// 답변 시트가 이미 떠 있는가. 알림 탭과 앱 재개는 순서가 정해져 있지 않아서
  /// 같은 알림에 대해 두 경로가 모두 불릴 수 있다. 시트가 두 장 겹치면 하나를
  /// 닫아도 같은 게 또 있어서 사용자는 답이 안 먹힌 줄 안다.
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(notificationBackendProvider).requestPermissions();
      await _onResume();
      if (mounted) await _continueOnboarding();
      if (mounted) await maybeShowWinterPrompt(context, ref);
      // 온보딩·겨울 카드보다 뒤에 둔다. 알림을 탭해 들어온 사람은 답을 하러
      // 온 것이므로, 앞의 것들을 치우고 나서 마지막에 시트를 띄운다.
      if (mounted) await _maybeShowAnswerSheet();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 포그라운드 진입은 재예약 트리거 중 하나다.
    if (state == AppLifecycleState.resumed) _onResume();
  }

  /// 온보딩을 끝까지 본 사람은 곧장 식물 추가로 이어진다 (명세 §3).
  /// 플래그는 한 번 쓰고 바로 내린다 — 다음 실행에 또 뜨면 안 된다.
  Future<void> _continueOnboarding() async {
    if (!ref.read(startAddPlantProvider)) return;
    ref.read(startAddPlantProvider.notifier).state = false;

    // 등록을 마치면 방금 추가한 식물이 있는 '내 식물' 탭으로 보낸다.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddPlantScreen()),
    );
    if (mounted && (ref.read(plantListProvider).value?.isNotEmpty ?? false)) {
      setState(() => _index = 1);
    }
  }

  Future<void> _onResume() async {
    final notifier = ref.read(plantListProvider.notifier);
    await notifier.drainPendingNotificationActions();
    await notifier.load(); // load() 안에서 rescheduleAll 이 돈다
    if (mounted) await _maybeShowAnswerSheet();
  }

  /// 알림 본문을 탭해 들어왔다면 그 식물의 답변 시트를 띄운다.
  ///
  /// **오늘 확인 대상이 아닌 식물은 건너뛴다.** 며칠 지난 알림을 뒤늦게 탭한
  /// 경우인데, 이미 답을 받은 식물에 버튼을 또 내밀면 같은 날 응답이 두 번
  /// 들어가 학습 factor 가 틀어진다. 그 경우엔 평소처럼 '오늘' 목록만 보인다.
  Future<void> _maybeShowAnswerSheet() async {
    final plantId = ref.read(answerPromptPlantIdProvider);
    if (plantId == null || _sheetOpen) return;

    Plant? target;
    for (final p in ref.read(todayPlantsProvider)) {
      if (p.id == plantId) target = p;
    }

    // 띄우든 못 띄우든 표시는 내린다. 남겨두면 다음 재개 때 엉뚱한 시점에
    // 시트가 튀어나온다.
    ref.read(answerPromptPlantIdProvider.notifier).state = null;
    if (target == null || !mounted) return;

    // 시트를 닫았을 때 그 식물이 보이는 탭이어야 한다. 답을 미루고 닫은
    // 사람이 '설정' 화면에 남겨지면 다시 찾아 들어가야 한다.
    setState(() => _index = 0);

    _sheetOpen = true;
    try {
      await showSoilAnswerSheet(context, ref, target);
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    // 알림 탭이 앱 재개보다 늦게 도착하는 경우가 있다. 그때는 [_onResume] 이
    // 이미 지나간 뒤라 여기서 받아야 한다.
    ref.listen<String?>(answerPromptPlantIdProvider, (_, next) {
      if (next != null) _maybeShowAnswerSheet();
    });

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TodayScreen(),
          PlantsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.wb_sunny_outlined),
            selectedIcon: const Icon(Icons.wb_sunny),
            label: s.tabToday,
          ),
          NavigationDestination(
            icon: const Icon(Icons.local_florist_outlined),
            selectedIcon: const Icon(Icons.local_florist),
            label: s.tabPlants,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: s.tabSettings,
          ),
        ],
      ),
    );
  }
}
