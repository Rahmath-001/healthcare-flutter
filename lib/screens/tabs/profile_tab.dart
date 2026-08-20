import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../features/settings/presentation/account_controller.dart';
import '../../l10n/l10n.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final profile = ref.watch(patientProfileProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            floating: true,
            title: Text('Profile'),
            centerTitle: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundImage: (session?.photoUrl != null)
                            ? NetworkImage(session!.photoUrl!)
                            : null,
                        child: (session?.photoUrl == null)
                            ? const Icon(Icons.person, size: 44)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(session?.greetingName ?? 'there',
                          style: theme.textTheme.headlineSmall),
                      if (session?.phone != null) ...[
                        const SizedBox(height: 4),
                        Text(session!.phone!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Blood group and age used to be read from SharedPreferences.
                // They are clinical data, so they live server-side in
                // patientProfiles and arrive with GET /v1/me. Age is derived
                // from the date of birth rather than stored, because a stored
                // age is wrong within a year.
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.bloodtype_outlined),
                        title: Text(context.l10n.profileBloodGroup),
                        trailing: Text(
                          profile.value?.bloodGroup?.label ?? '—',
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.cake_outlined),
                        title: Text(context.l10n.profileAge),
                        trailing: Text(
                          profile.value?.age?.toString() ?? '—',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(context.l10n.profileEditProfile),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.editProfile),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: const Text('Prescriptions'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go(Routes.prescriptions),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: const Text('Who can see my records'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.sharing),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.support_agent),
                        title: const Text('Help and support'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.supportTickets),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: const Text('Settings'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.settings),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.logout, color: theme.colorScheme.error),
                    title: Text('Sign out',
                        style: TextStyle(color: theme.colorScheme.error)),
                    onTap: () =>
                        ref.read(sessionControllerProvider.notifier).signOut(),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
