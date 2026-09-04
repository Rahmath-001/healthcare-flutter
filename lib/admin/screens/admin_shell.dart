import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../admin_app.dart';
import '../router/admin_router.dart';
import '../theme/admin_theme.dart';

/// Chrome around every console screen.
///
/// A rail rather than a bottom bar, and it collapses to icons on a narrow
/// window rather than disappearing — an operator on a laptop with a browser
/// docked beside a video call still needs to move between the queue and a
/// ticket.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final scopes = ref.watch(operatorScopesProvider);
    final theme = Theme.of(context);

    final destinations = <_Destination>[
      // First, because "what needs me" is the question an operator opens the
      // console with.
      const _Destination(
        path: AdminRoutes.dashboard,
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: 'Overview',
      ),
      if (scopes.canReviewProviders)
        const _Destination(
          path: AdminRoutes.queue,
          icon: Icons.fact_check_outlined,
          selectedIcon: Icons.fact_check,
          label: 'Verification',
        ),
      if (scopes.canDecideProviders)
        const _Destination(
          path: AdminRoutes.hospitals,
          icon: Icons.local_hospital_outlined,
          selectedIcon: Icons.local_hospital,
          label: 'Hospitals',
        ),
      if (scopes.canSuspendAccounts)
        const _Destination(
          path: AdminRoutes.users,
          icon: Icons.manage_accounts_outlined,
          selectedIcon: Icons.manage_accounts,
          label: 'Accounts',
        ),
      if (scopes.canReviewProviders)
        const _Destination(
          path: AdminRoutes.ratings,
          icon: Icons.reviews_outlined,
          selectedIcon: Icons.reviews,
          label: 'Ratings',
        ),
      if (scopes.canReadTickets)
        const _Destination(
          path: AdminRoutes.tickets,
          icon: Icons.support_agent_outlined,
          selectedIcon: Icons.support_agent,
          label: 'Support',
        ),
      // Behind the same scope as suspending an account: reading who saw whose
      // records is at least as sensitive as ending a session, and it is the
      // operators who already act on accounts who need it.
      if (scopes.canSuspendAccounts)
        const _Destination(
          path: AdminRoutes.audit,
          icon: Icons.history_toggle_off_outlined,
          selectedIcon: Icons.history_toggle_off,
          label: 'Access log',
        ),
    ];

    final selected = destinations.indexWhere(
      (d) => location == d.path || location.startsWith('${d.path}/'),
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.local_hospital_outlined,
                color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Text('MiDoctor Operations'),
          ],
        ),
        actions: [
          if (session != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    session.greetingName,
                    style: theme.textTheme.labelLarge,
                  ),
                  Text(
                    session.role.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(sessionControllerProvider.notifier).signOut(),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: Row(
        children: [
          if (destinations.isNotEmpty)
            NavigationRail(
              selectedIndex: selected >= 0 ? selected : null,
              onDestinationSelected: (i) => context.go(destinations[i].path),
              labelType: MediaQuery.sizeOf(context).width > 1000
                  ? NavigationRailLabelType.all
                  : NavigationRailLabelType.selected,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: kAdminMaxContentWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
