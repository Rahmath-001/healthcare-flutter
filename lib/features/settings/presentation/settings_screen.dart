import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../l10n/l10n.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: CircleAvatar(
              backgroundImage: session?.photoUrl != null
                  ? NetworkImage(session!.photoUrl!)
                  : null,
              child: session?.photoUrl == null
                  ? const Icon(Icons.person_outline)
                  : null,
            ),
            title: Text(session?.greetingName ?? 'You'),
            subtitle: Text(session?.phone ?? session?.email ?? ''),
          ),
          const Divider(),
          _SectionHeader(label: 'Your details', theme: theme),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(context.l10n.profileEditProfile),
            subtitle:
                const Text('Name, blood group, allergies, emergency contact'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.editProfile),
          ),
          const Divider(),
          _SectionHeader(label: 'Privacy and data', theme: theme),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Who can see my records'),
            subtitle: const Text('Manage sharing and view the access log'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.sharing),
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: Text(context.l10n.settingsPrivacy),
            subtitle: const Text('Export your data, or delete your account'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.privacy),
          ),
          const Divider(),
          _SectionHeader(label: 'Support', theme: theme),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Help and support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.supportTickets),
          ),
          const Divider(),
          _SectionHeader(label: 'Account', theme: theme),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('Signed-in devices'),
            subtitle: Text('This device · session ${session?.sessionId ?? ''}'),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(context.l10n.actionSignOut,
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => ref.read(sessionControllerProvider.notifier).signOut(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          label,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.primary),
        ),
      );
}
