import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/session/user_role.dart';

/// The account type selected at the beginning of registration.
class RequestedRoleNotifier extends Notifier<UserRole> {
  @override
  UserRole build() => UserRole.patient;

  void select(UserRole role) {
    assert(role == UserRole.patient || role == UserRole.provider);
    state = role;
  }
}

final requestedRoleProvider = NotifierProvider<RequestedRoleNotifier, UserRole>(
  RequestedRoleNotifier.new,
);

/// The client-facing registration choice screen. Patient and provider create
/// mobile accounts; organisation entries collect a registration request rather
/// than pretending an unsupported role has been granted access.
class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    void openPerson(UserRole role) {
      ref.read(requestedRoleProvider.notifier).select(role);
      context.push(Routes.consent);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('MiDoctor')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                Text('Register as', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Choose the account that best describes you.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                _RegistrationOption(
                  icon: Icons.person_outline,
                  title: 'Patient',
                  description: 'Find doctors, book care and manage your records.',
                  onTap: () => openPerson(UserRole.patient),
                ),
                _RegistrationOption(
                  icon: Icons.medical_services_outlined,
                  title: 'Doctor / Provider',
                  description: 'Offer consultations and manage your practice.',
                  onTap: () => openPerson(UserRole.provider),
                ),
                _RegistrationOption(
                  icon: Icons.local_hospital_outlined,
                  title: 'Hospital',
                  description: 'Register your hospital and business address.',
                  onTap: () => context.push(
                    '${Routes.organisationRegistration}?type=Hospital',
                  ),
                ),
                _RegistrationOption(
                  icon: Icons.biotech_outlined,
                  title: 'Lab / Diagnostics',
                  description: 'Register a diagnostic centre with MiDoctor.',
                  onTap: () => context.push(
                    '${Routes.organisationRegistration}?type=Lab%20%2F%20Diagnostics',
                  ),
                ),
                _RegistrationOption(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Home Health Provider',
                  description: 'Register a home-health service with MiDoctor.',
                  onTap: () => context.push(
                    '${Routes.organisationRegistration}?type=Home%20Health%20Provider',
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

class _RegistrationOption extends StatelessWidget {
  const _RegistrationOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.primary,
                  child: Icon(icon),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(description, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
