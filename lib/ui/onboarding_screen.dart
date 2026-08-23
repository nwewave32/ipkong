import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// 온보딩 3화면 (명세 §3 — 스킵 가능).
///
/// 파는 게 아니라 **약속을 하는** 화면이다. 경쟁 앱들이 온보딩에서 종
/// 식별·계정 생성·알림 권한을 한꺼번에 요구하다 이탈을 만드는 걸 피하려고,
/// 여기서는 아무것도 입력받지 않는다. 읽고 넘기기만 하면 된다.
///
/// 세 장의 순서에는 이유가 있다.
///
/// 1. **왜 이 앱인가** — 과습이 식물을 죽이는 1순위이고, 이 앱은 알림을
///    줄이는 쪽으로 틀린다. 스토어 1번 컷과 같은 메시지다.
/// 2. **무엇을 요구하는가** — 탭 한 번. 그 한 번이 주기를 어떻게 고치는지.
/// 3. **얼마나 조용한가** — 하루 1개. 마지막에 v1.1 티저 한 줄 (§10.1).
///
/// 스킵은 언제나 우상단에 있고, 스킵도 '봤다'로 기록한다. 거절한 화면을
/// 다시 들이밀지 않기 위해서다.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pageCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// [startAddPlant] 가 true 면 홈에 도착하자마자 식물 추가 화면이 열린다.
  /// 명세 §3 의 첫 실행 플로우가 온보딩 → 식물 추가이기 때문이다.
  /// 건너뛴 사람에게까지 입력 화면을 들이밀지는 않는다.
  Future<void> _finish({required bool startAddPlant}) async {
    await ref.read(settingsRepositoryProvider).setOnboardingDone(true);
    if (!mounted) return;
    ref.read(startAddPlantProvider.notifier).state = startAddPlant;
    ref.read(onboardingDoneProvider.notifier).state = true;
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      _finish(startAddPlant: true);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isLast = _page == _pageCount - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TextButton(
                  onPressed: () => _finish(startAddPlant: false),
                  child: Text(s.skip),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Page(
                    emoji: '💧',
                    title: s.onboard1Title,
                    body: s.onboard1Body,
                  ),
                  _Page(
                    emoji: '👆',
                    title: s.onboard2Title,
                    body: s.onboard2Body,
                  ),
                  _Page(
                    emoji: '🔔',
                    title: s.onboard3Title,
                    body: s.onboard3Body,
                    // §10.1 — 설정 외에 온보딩 마지막 화면에도 한 줄.
                    // 강요하지 않는다. 버튼도 팝업도 없이 문장 하나다.
                    footnote: '✈️ ${s.careLinkTitle} — ${s.careLinkNextUpdate}',
                  ),
                ],
              ),
            ),
            _Dots(count: _pageCount, index: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(isLast ? s.onboardStart : s.onboardNext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.emoji,
    required this.title,
    required this.body,
    this.footnote,
  });

  final String emoji;
  final String title;
  final String body;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 내용이 들어가면 가운데 정렬, 넘치면 스크롤. 둘 중 하나만 고르면
    // 큰 화면에서는 글이 위로 쏠리고 작은 화면에서는 잘린다.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 72)),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              if (footnote != null) ...[
                const SizedBox(height: 32),
                Text(
                  footnote!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
