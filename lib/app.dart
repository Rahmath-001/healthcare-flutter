import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/onboarding_service.dart';
import 'widgets/offline_banner.dart';

class HealthcareApp extends StatelessWidget {
  const HealthcareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Healthcare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0E8388),
        useMaterial3: true,
      ),
      builder: (context, child) => Column(
        children: [
          const OfflineBanner(),
          Expanded(child: child!),
        ],
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final onboarding = context.read<OnboardingService>();

    final Widget screen;
    final String key;

    if (!auth.isSignedIn) {
      screen = const LoginScreen();
      key = 'login';
    } else if (!onboarding.isComplete) {
      screen = const OnboardingScreen();
      key = 'onboarding';
    } else {
      screen = const DashboardScreen();
      key = 'dashboard';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(key: ValueKey(key), child: screen),
    );
  }
}
