import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/session/user_role.dart';
import '../../../l10n/l10n.dart';

/// Which role the user is registering as, chosen before sign-up begins.
///
/// FR-AUTH-002 allows exactly two self-assignable roles: Patient and Provider.
/// The other five in the RBAC matrix (Supervisor, Support L1/L2, Admin) are
/// provisioned internally and can never be picked here — otherwise anyone could
/// claim approval rights over doctors.
///
/// Choosing Provider does not grant provider access. It routes the account into
/// verification, where it holds `profile:read` and `credentials:submit` and
/// nothing else until a supervisor approves it.
class RequestedRoleNotifier extends Notifier<UserRole> {
  @override
  UserRole build() => UserRole.patient;

  void select(UserRole role) {
    assert(
      role == UserRole.patient || role == UserRole.provider,
      'Only Patient and Provider are self-assignable (FR-AUTH-002)',
    );
    state = role;
  }
}

/// Carried into the session exchange as `requestedRole`. The server decides the
/// actual role; this is a request, not an assertion.
final requestedRoleProvider = NotifierProvider<RequestedRoleNotifier, UserRole>(
  RequestedRoleNotifier.new,
);

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(requestedRoleProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create an account')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 8),
                  Text(context.l10n.authRoleTitle,
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'You can only change this later by contacting support, so '
                    'please pick the one that fits.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  _RoleCard(
                    role: UserRole.patient,
                    selected: selected == UserRole.patient,
                    icon: Icons.person_outline,
                    title: context.l10n.authRolePatient,
                    description:
                        'Find doctors, book consultations, and keep your '
                        'health records in one place.',
                    onTap: () => ref
                        .read(requestedRoleProvider.notifier)
                        .select(UserRole.patient),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    role: UserRole.provider,
                    selected: selected == UserRole.provider,
                    icon: Icons.medical_services_outlined,
                    title: context.l10n.authRoleProvider,
                    description: 'See patients, manage your schedule and issue '
                        'prescriptions.',
                    footnote: 'You will need to upload your degree, council '
                        'registration and hospital affiliation, and turn on '
                        'two-factor authentication before you can see '
                        'patients.',
                    onTap: () => ref
                        .read(requestedRoleProvider.notifier)
                        .select(UserRole.provider),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: theme.colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'MiDoctor staff accounts are created internally and '
                          'cannot be registered here.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => context.push(Routes.signup),
                  child: const Text('Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.footnote,
  });

  final UserRole role;
  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final String? footnote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(description, style: theme.textTheme.bodyMedium),
                    if (footnote != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        footnote!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
