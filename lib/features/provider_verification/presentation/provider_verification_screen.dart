import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/session/user_role.dart';

/// The only screen an unverified provider can reach.
///
/// This is the RBAC matrix rendered as a screen: a provider who is not APPROVED
/// holds just `profile:read` and `credentials:submit`, so there is no schedule,
/// no patients, and no consultations to show them.
///
/// It reports verification state and, where the status still permits a
/// submission, routes into the credential checklist nested beneath it.
class ProviderVerificationScreen extends ConsumerWidget {
  const ProviderVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final status = session?.providerStatus ?? ProviderStatus.draft;
    final theme = Theme.of(context);
    final (icon, title, body) = _copyFor(status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(title,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(body,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              if (_canSubmit(status))
                FilledButton.icon(
                  onPressed: () => context.push(Routes.providerCredentials),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(status == ProviderStatus.resubmitRequested
                      ? 'Resubmit documents'
                      : 'Submit documents'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _canSubmit(ProviderStatus status) =>
      status == ProviderStatus.draft ||
      status == ProviderStatus.rejected ||
      status == ProviderStatus.resubmitRequested;

  static (IconData, String, String) _copyFor(ProviderStatus status) =>
      switch (status) {
        ProviderStatus.draft => (
            Icons.assignment_outlined,
            'Complete your profile',
            'Upload your degree certificate, medical registration, identity '
                'proof and hospital affiliation to start seeing patients.',
          ),
        ProviderStatus.submitted || ProviderStatus.underReview => (
            Icons.hourglass_top_outlined,
            'Verification in progress',
            'Our team is reviewing your documents. This usually takes 2–3 '
                'working days, and we will notify you as soon as it is done.',
          ),
        ProviderStatus.rejected => (
            Icons.error_outline,
            'Verification unsuccessful',
            'We could not verify your documents. Check the reason sent to you '
                'and submit again.',
          ),
        ProviderStatus.resubmitRequested => (
            Icons.refresh_outlined,
            'More information needed',
            'Some of your documents need to be resubmitted. Please review the '
                'notes we sent and upload them again.',
          ),
        ProviderStatus.suspended => (
            Icons.pause_circle_outline,
            'Account under review',
            'Your provider account is temporarily suspended pending a review. '
                'Please contact MiDoctor support.',
          ),
        ProviderStatus.deactivated => (
            Icons.person_off_outlined,
            'Account deactivated',
            'Your provider account has been deactivated. Contact support if '
                'you would like to reactivate it.',
          ),
        ProviderStatus.approved || ProviderStatus.notApplicable => (
            Icons.verified_outlined,
            'Verified',
            'Your account is verified.',
          ),
      };
}
