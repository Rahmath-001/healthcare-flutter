import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/onboarding_service.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final onboarding = context.read<OnboardingService>();
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
                        backgroundImage: (user?.photoUrl != null)
                            ? NetworkImage(user!.photoUrl!)
                            : null,
                        child: (user?.photoUrl == null)
                            ? const Icon(Icons.person, size: 44)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(user?.greetingName ?? 'there',
                          style: theme.textTheme.headlineSmall),
                      if (user?.phone != null) ...[
                        const SizedBox(height: 4),
                        Text(user!.phone!),
                      ],
                      const SizedBox(height: 4),
                      Text('Signed in via ${user?.provider ?? 'unknown'}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.bloodtype_outlined),
                        title: const Text('Blood group'),
                        trailing: Text(onboarding.bloodGroup ?? '-'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.cake_outlined),
                        title: const Text('Age range'),
                        trailing: Text(onboarding.age ?? '-'),
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
                    onTap: () => context.read<AuthService>().signOut(),
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
