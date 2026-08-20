import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failure.dart';
import '../../core/providers.dart';
import '../../core/service_providers.dart';
import '../admin_app.dart';

/// Operator sign-in.
///
/// Google only. Staff accounts are provisioned by an administrator and belong
/// to a workspace identity — there is no self-service sign-up here, and phone
/// OTP would be the wrong factor for an account that can approve doctors.
///
/// A patient or provider signing in successfully still lands back here with a
/// refusal: authentication proves who they are, and this console is not for
/// them. That check is repeated server-side on every request, where it counts.
class OperatorSignInScreen extends ConsumerStatefulWidget {
  const OperatorSignInScreen({super.key});

  @override
  ConsumerState<OperatorSignInScreen> createState() =>
      _OperatorSignInScreenState();
}

class _OperatorSignInScreenState extends ConsumerState<OperatorSignInScreen> {
  bool _busy = false;
  String? _error;

  /// Signs in against the fixture backend, with no identity provider involved.
  Future<void> _sampleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).signInWithSampleData();
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message;
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      if (!ref.read(authServiceProvider).isSignedIn) {
        // Dismissing the Google sheet is not an error.
        if (mounted) setState(() => _busy = false);
        return;
      }

      await ref
          .read(sessionControllerProvider.notifier)
          .completeFirebaseSignIn();

      final session = ref.read(currentSessionProvider);
      if (!isOperator(session)) {
        // Signed in as a real person who simply is not staff. Drop the session
        // rather than leaving them holding one this console cannot use.
        await ref.read(sessionControllerProvider.notifier).signOut();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'That account does not have access to the operations '
              'console. Patients and doctors use the MiDoctor app.';
        });
      }
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.local_hospital_outlined,
                    size: 44,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'MiDoctor Operations',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Provider verification, account administration and support.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (ref.watch(useFixturesProvider)) ...[
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _sampleSignIn,
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Open with sample data'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Running on sample data. Actions that would change a real '
                      'account are refused rather than faked.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _busy || ref.watch(useFixturesProvider)
                          ? null
                          : _signIn,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : const Icon(Icons.login),
                      label:
                          Text(_busy ? 'Signing in…' : 'Continue with Google'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Staff accounts are provisioned by an administrator. '
                    'There is no sign-up here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
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
