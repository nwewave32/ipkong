import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/providers.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding_screen.dart';

class IpkongApp extends ConsumerWidget {
  const IpkongApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final onboarded = ref.watch(onboardingDoneProvider);

    return MaterialApp(
      title: '잎콩',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      // 온보딩을 라우트로 밀어 넣지 않고 첫 화면 자체로 둔다. 첫 프레임 뒤에
      // push 하면 빈 '오늘' 화면이 한 번 번쩍이고, 그게 첫인상이 된다.
      home: onboarded ? const HomeShell() : const OnboardingScreen(),
    );
  }

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4C9A5A),
        brightness: brightness,
      ),
    );
  }
}
