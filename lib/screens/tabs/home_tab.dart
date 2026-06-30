import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../widgets/shimmer_placeholder.dart';
import '../doctors_screen.dart';
import '../medications_screen.dart';

class HomeTab extends StatefulWidget {
  /// Lets quick actions switch the parent Dashboard's bottom-nav tab.
  final void Function(int tabIndex)? onNavigateTab;

  const HomeTab({super.key, this.onNavigateTab});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
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
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final theme = Theme.of(context);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            floating: true,
            title: Text('Home'),
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
                                  backgroundImage: (user?.photoUrl != null)
                                      ? NetworkImage(user!.photoUrl!)
                                      : null,
                                  child: (user?.photoUrl == null)
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
                                        'Hello, ${user?.greetingName ?? 'there'}',
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
                Text('Quick actions', style: theme.textTheme.titleSmall),
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
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DoctorsScreen()),
                      ),
                    ),
                    _QuickAction(
                      icon: Icons.description_outlined,
                      label: 'View Records',
                      onTap: () => widget.onNavigateTab?.call(2),
                    ),
                    _QuickAction(
                      icon: Icons.medication_outlined,
                      label: 'Medications',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MedicationsScreen()),
                      ),
                    ),
                    _QuickAction(
                      icon: Icons.support_agent,
                      label: 'Contact Support',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Support: support@healthcare.app')),
                      ),
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
