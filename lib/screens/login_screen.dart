import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/router/routes.dart';
import '../core/service_providers.dart';
import '../widgets/apple_button.dart';
import '../widgets/google_button.dart';
import '../widgets/primary_button.dart';
import '../l10n/l10n.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _googleLoading = false;
  bool _sampleLoading = false;
  bool _appleLoading = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _sampleSignIn() async {
    setState(() => _sampleLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signInWithSampleData();
    } finally {
      if (mounted) setState(() => _sampleLoading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      // Firebase proved who they are; this turns that into a session
      // that says what they may do. Without it the router sees no
      // session and bounces straight back to sign-in.
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _apple() async {
    setState(() => _appleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithApple();
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Apple sign-in failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Hero(
                  tag: 'app-logo',
                  child: ScaleTransition(
                    scale: _pulse,
                    child: Icon(Icons.health_and_safety,
                        size: 72, color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.authWelcomeBack,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(context.l10n.authSignInToContinue,
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),
              // Sample data has no identity provider behind it, so every other
              // button here would die at a Google consent sheet that cannot
              // return. Without this the mock data is unreachable: the app
              // opens on a sign-in screen it cannot get past.
              if (ref.watch(useFixturesProvider)) ...[
                PrimaryButton(
                  label: context.l10n.authSampleData,
                  loading: _sampleLoading,
                  onPressed: _sampleSignIn,
                ),
                const SizedBox(height: 14),
                Text(
                  'Signs in as Priya Sharma, a patient with appointments, '
                  'records and prescriptions already in place.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
              PrimaryButton(
                label: context.l10n.authContinueWithPhone,
                onPressed: () => context.push(Routes.phone),
              ),
              const SizedBox(height: 14),
              GoogleButton(onPressed: _google, loading: _googleLoading),
              // Absent on Android and web, and while the availability check is
              // still resolving — a button that flashes in after the fact reads
              // as a glitch.
              ...ref.watch(appleSignInAvailableProvider).maybeWhen(
                    data: (available) => available
                        ? [
                            const SizedBox(height: 14),
                            AppleButton(
                                onPressed: _apple, loading: _appleLoading),
                          ]
                        : const <Widget>[],
                    orElse: () => const <Widget>[],
                  ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(context.l10n.authNewHere),
                  TextButton(
                    onPressed: () => context.push(Routes.roleSelection),
                    child: Text(context.l10n.authCreateAccount),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
