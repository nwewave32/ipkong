import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'add_plant_screen.dart';
import 'plants_screen.dart';
import 'settings_screen.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(notificationBackendProvider).requestPermissions();
      await _onResume();
      if (mounted) await _continueOnboarding();
      if (mounted) await maybeShowWinterPrompt(context, ref);
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
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

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
