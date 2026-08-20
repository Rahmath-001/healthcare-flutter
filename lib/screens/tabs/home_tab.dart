import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../l10n/l10n.dart';
import '../../widgets/shimmer_placeholder.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text(context.l10n.navHome),
            centerTitle: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: !_loaded
                      ? ShimmerPlaceholder.rect(height: 90)
                      : Card(
                          key: const ValueKey('greeting'),
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundImage: (session?.photoUrl != null)
                                      ? NetworkImage(session!.photoUrl!)
                                      : null,
                                  child: (session?.photoUrl == null)
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hello, ${session?.greetingName ?? 'there'}',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Welcome back to your health hub',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                Text(context.l10n.homeQuickActions,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.3,
                  children: [
                    _QuickAction(
                      icon: Icons.calendar_month,
                      label: 'Book Appointment',
                      onTap: () => context.go(Routes.doctorSearch),
                    ),
                    _QuickAction(
                      icon: Icons.description_outlined,
                      label: 'View Records',
                      onTap: () => context.go(Routes.patientRecords),
                    ),
                    // The Medications tile is deliberately gone: the module maps
                    // to no functional requirement and implies adherence
                    // tracking and drug-interaction liability nobody scoped.
                    _QuickAction(
                      icon: Icons.event_note_outlined,
                      label: 'My Appointments',
                      onTap: () => context.go(Routes.patientAppointments),
                    ),
                    _QuickAction(
                      icon: Icons.receipt_long_outlined,
                      label: 'Prescriptions',
                      onTap: () => context.go(Routes.prescriptions),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
