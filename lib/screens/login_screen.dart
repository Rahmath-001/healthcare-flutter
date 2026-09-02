import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/router/routes.dart';
import '../core/service_providers.dart';
import '../core/session/user_role.dart';
import '../core/theme/app_tokens.dart';
import '../shared/widgets/app_motion.dart';
import '../widgets/apple_button.dart';
import '../widgets/google_button.dart';
import '../widgets/primary_button.dart';
import '../l10n/l10n.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.showWireframeSignIn = false});

  /// The client wireframe's full sign-in page, used from the public catalogue
  /// and when booking as a guest.
  final bool showWireframeSignIn;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _googleLoading = false;
  bool _sampleLoading = false;
  bool _appleLoading = false;

  bool get _busy => _googleLoading || _sampleLoading || _appleLoading;

  Future<void> _sampleSignIn({
    UserRole role = UserRole.patient,
    ProviderStatus? providerStatus,
  }) async {
    setState(() => _sampleLoading = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signInWithSampleData(
            requestedRole: role,
            providerStatus: providerStatus,
          );
    } finally {
      if (mounted) setState(() => _sampleLoading = false);
    }
  }

  Future<void> _google() async {
    // Resolved before the first await: after it, this `State`'s context may be
    // gone, and reaching for localisations through a defunct element is the
    // `use_build_context_synchronously` lint's actual failure mode.
    final l10n = context.l10n;
    setState(() => _googleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      // Firebase proved who they are; this turns that into a session
      // that says what they may do. Without it the router sees no
      // session and bounces straight back to sign-in.
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
    } catch (_) {
      // The exception text is not shown. It is a Firebase/Dio message written
      // for a developer, and on a failed sign-in it can carry the identifier
      // the user typed straight into a snackbar someone else can read over
      // their shoulder.
      _showError(l10n.authGoogleFailed);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _apple() async {
    final l10n = context.l10n;
    setState(() => _appleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithApple();
      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();
    } catch (_) {
      _showError(l10n.authAppleFailed);
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      // Otherwise two failed attempts queue, and the second message waits out
      // the first before appearing.
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useFixtures = ref.watch(useFixturesProvider);

    if (widget.showWireframeSignIn) {
      return _BookingWireframeSignIn(
        busy: _busy,
        googleLoading: _googleLoading,
        appleLoading: _appleLoading,
        onGoogle: _google,
        onApple: _apple,
        onMobile: () => context.push(Routes.phone),
        onRegister: () => context.go(Routes.roleSelection),
        onCancel: () => context.go(Routes.landing),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('MiDoctor'),
        leading: IconButton(
          tooltip: 'Cancel sign in',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go(Routes.landing),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Sign-in is a form; a form stretched across a tablet or the web
            // build puts a 900px-wide button under a 900px-wide heading.
            constraints:
                const BoxConstraints(maxWidth: Breakpoints.readableWidth),
            child: SingleChildScrollView(
              // Scrollable, not a centred Column. With the sample-data block,
              // phone, Google and Apple all present this content is taller
              // than a 4.7" screen in landscape, and the old layout answered
              // that with a yellow overflow stripe.
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.xl,
                vertical: Insets.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Wordmark(),
                  const SizedBox(height: Insets.xl),
                  FadeSlideIn(
                    index: 1,
                    child: Column(
                      children: [
                        Text(
                          'Sign in with',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: Insets.sm),
                        Text(
                          'Google, Apple, or your mobile phone.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Insets.xxl),

                  // Sample data has no identity provider behind it, so every
                  // other button here would die at a Google consent sheet that
                  // cannot return. Without this the mock data is unreachable:
                  // the app opens on a sign-in screen it cannot get past.
                  if (useFixtures) ...[
                    FadeSlideIn(
                        index: 2,
                        child: _SampleDataPanel(
                          loading: _sampleLoading,
                          busy: _busy,
                          onPatient: _sampleSignIn,
                          onDoctor: () => _sampleSignIn(
                            role: UserRole.provider,
                            providerStatus: ProviderStatus.approved,
                          ),
                          onPendingDoctor: () => _sampleSignIn(
                            role: UserRole.provider,
                            providerStatus: ProviderStatus.draft,
                          ),
                        )),
                    const SizedBox(height: Insets.xl),
                    const _OrDivider(),
                    const SizedBox(height: Insets.xl),
                  ],

                  FadeSlideIn(
                    index: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GoogleButton(
                          onPressed: _busy ? null : _google,
                          loading: _googleLoading,
                        ),
                        // Absent on Android and web, and while the availability
                        // check is still resolving — a button that flashes in
                        // after the fact reads as a glitch.
                        ...ref.watch(appleSignInAvailableProvider).maybeWhen(
                              data: (available) => available
                                  ? [
                                      const SizedBox(height: Insets.md),
                                      AppleButton(
                                        onPressed: _busy ? null : _apple,
                                        loading: _appleLoading,
                                      ),
                                    ]
                                  : const <Widget>[],
                              orElse: () => const <Widget>[],
                            ),
                        const SizedBox(height: Insets.md),
                        PrimaryButton(
                          label: context.l10n.authContinueWithPhone,
                          onPressed:
                              _busy ? null : () => context.push(Routes.phone),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Insets.xl),
                  FadeSlideIn(
                    index: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            context.l10n.authNewHere,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => context.push(Routes.roleSelection),
                          child: Text(context.l10n.authCreateAccount),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-page guest booking sign-in, matching page 6 of the client wireframe.
/// It deliberately uses the existing login route so [returnTo] remains
/// allow-listed by the router after the user authenticates.
class _BookingWireframeSignIn extends StatelessWidget {
  const _BookingWireframeSignIn({
    required this.busy,
    required this.googleLoading,
    required this.appleLoading,
    required this.onGoogle,
    required this.onApple,
    required this.onMobile,
    required this.onRegister,
    required this.onCancel,
  });

  final bool busy;
  final bool googleLoading;
  final bool appleLoading;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onMobile;
  final VoidCallback onRegister;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MiDoctor'),
        leading: IconButton(
          tooltip: 'Cancel sign in',
          icon: const Icon(Icons.close_rounded),
          onPressed: onCancel,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: Breakpoints.readableWidth),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: Insets.md),
                  child: Text(
                    'Sign In with',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        Insets.xl, Insets.xxl, Insets.xl, Insets.xl),
                    children: [
                      _SignInOption(
                        label: 'Google Sign in',
                        icon: Icons.g_mobiledata,
                        loading: googleLoading,
                        onTap: busy ? null : onGoogle,
                      ),
                      const SizedBox(height: Insets.md),
                      _SignInOption(
                        label: 'Apple Sign in',
                        icon: Icons.apple,
                        loading: appleLoading,
                        onTap: busy ? null : onApple,
                      ),
                      const SizedBox(height: Insets.md),
                      _SignInOption(
                        label: 'Mobile Sign in',
                        icon: Icons.phone_android_outlined,
                        onTap: busy ? null : onMobile,
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Insets.xl, Insets.sm, Insets.xl, Insets.xl),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: busy ? null : onRegister,
                            child: const Text('Register'),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: OutlinedButton(
                            // This screen is the Login destination; keeping
                            // the visible Login action mirrors the client
                            // wireframe without changing the active route.
                            onPressed: () => FocusScope.of(context).unfocus(),
                            child: const Text('Login'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInOption extends StatelessWidget {
  const _SignInOption({
    required this.label,
    required this.icon,
    this.loading = false,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: Radii.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.mdAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: theme.textTheme.titleLarge),
                ),
                if (loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else
                  Icon(icon, size: 30, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark, and the app's name under it.
///
/// It used to breathe on a two-second loop, forever. A perpetual animation on
/// a screen the user is reading gives the eye something to track that is not
/// the words, costs a frame every 16ms for as long as the screen is open, and
/// is exactly the kind of movement the OS "reduce motion" setting exists to
/// stop. It now settles once on arrival, like everything else in the app.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FadeSlideIn(
      offset: 0,
      child: Column(
        children: [
          Hero(
            tag: 'app-logo',
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: Radii.lgAll,
              ),
              child: Icon(
                Icons.health_and_safety,
                size: 44,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: Insets.md),
          Text(
            context.l10n.appTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              letterSpacing: 1.2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sample-data entry points, grouped so they read as one thing that is not
/// a real sign-in method.
class _SampleDataPanel extends StatelessWidget {
  const _SampleDataPanel({
    required this.loading,
    required this.busy,
    required this.onPatient,
    required this.onDoctor,
    required this.onPendingDoctor,
  });

  final bool loading;
  final bool busy;
  final VoidCallback onPatient;
  final VoidCallback onDoctor;
  final VoidCallback onPendingDoctor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton(
              label: context.l10n.authSampleData,
              loading: loading,
              onPressed: busy && !loading ? null : onPatient,
            ),
            const SizedBox(height: Insets.md),
            Text(
              context.l10n.authSampleDataHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Insets.sm),
            const Divider(),
            // The provider half of the binary is otherwise unreachable on
            // sample data: signing up as a doctor needs Firebase, and the
            // approval that opens the provider shell is an operator decision
            // taken in a console that does not share this process.
            TextButton(
              onPressed: busy ? null : onDoctor,
              child: Text(context.l10n.authExploreAsDoctor),
            ),
            TextButton(
              onPressed: busy ? null : onPendingDoctor,
              child: Text(context.l10n.authExploreAsPendingDoctor),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.md),
          child: Text(
            context.l10n.authOr,
            style: theme.textTheme.labelMedium,
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
