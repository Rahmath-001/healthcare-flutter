import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Terminal screen for accounts this app cannot serve.
///
/// Two distinct cases, deliberately given different copy:
///  * the account is suspended or deactivated;
///  * the role is real but has no mobile UI (supervisor, support, admin).
///
/// Neither is treated as a sign-out. Silently ejecting someone gives them no
/// way to understand what happened or to reach support.
class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final theme = Theme.of(context);

    final isStaffRole = session != null && !session.role.isSupportedOnMobile;

    final (title, body) = isStaffRole
        ? (
            'Use the web console',
            'The MiDoctor mobile app serves patients and doctors. Your account '
                'has a staff role, which is managed from the web console.',
          )
        : (
            'Account unavailable',
            'This account is currently suspended. Please contact MiDoctor '
                'support if you believe this is a mistake.',
          );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isStaffRole
                    ? Icons.desktop_windows_outlined
                    : Icons.lock_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(title,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(body,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(sessionControllerProvider.notifier).signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
