import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// The provider shell's Profile tab.
///
/// The shell, its routes and its role gating are real and testable now; the
/// content arrives with the features that fill it:
///   * Today / Schedule  → Phase 3 (availability + booking)
///   * Patients          → Phase 4 (records + consent)
///
/// Building the shell first means each screen is written once, into a structure
/// that already exists, rather than being retrofitted later.
class ProviderProfileTab extends ConsumerWidget {
  const ProviderProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const CircleAvatar(
                child: Icon(Icons.medical_services_outlined)),
            title: Text(session?.greetingName ?? 'Doctor'),
            subtitle: Text(session?.phone ?? session?.email ?? ''),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Verification status'),
            subtitle: Text(session?.providerStatus.name ?? 'unknown'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(sessionControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}
