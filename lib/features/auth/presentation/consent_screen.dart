import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/session/user_role.dart';
import 'role_selection_screen.dart';

/// Required acknowledgement inserted between account selection and registration
/// as shown in the client wireframe. Both records are unchecked by default.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _privacyAccepted = false;
  bool _termsAccepted = false;

  @override
  Widget build(BuildContext context) {
    final isProvider = ref.watch(requestedRoleProvider) == UserRole.provider;
    final accepted = _privacyAccepted && _termsAccepted;
    final theme = Theme.of(context);
    final accountLabel = isProvider ? 'Doctor / Provider' : 'Patient';

    return Scaffold(
      appBar: AppBar(
        title: const Text('MiDoctor'),
        leading: IconButton(
          tooltip: 'Cancel registration',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go(Routes.landing),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$accountLabel Privacy and Access',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  Text('Welcome to MiDoctor', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Card(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: .45),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Before you continue, please review and accept the terms governing your use of MiDoctor Healthcare Marketplace.\n\n'
                        'Use MiDoctor only for authorised and lawful purposes. Keep your sign-in details secure, protect confidential medical information, and do not access or disclose another person\'s records without authorisation.\n\n'
                        'We may log activity to protect privacy and security. Please promptly report suspected unauthorised access, compromised credentials, privacy incidents, or accidental disclosure.\n\n'
                        'Unauthorised access, use, disclosure, modification, destruction, or attempted compromise of systems or information is strictly prohibited.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _privacyAccepted,
                    onChanged: (value) => setState(() => _privacyAccepted = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('I agree with the HIPAA Privacy & Data Security Policy'),
                  ),
                  CheckboxListTile(
                    value: _termsAccepted,
                    onChanged: (value) => setState(() => _termsAccepted = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('I agree to the Terms of Service'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: accepted ? () => context.push(Routes.signup) : null,
                        child: const Text('Register'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.go(Routes.landing),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
