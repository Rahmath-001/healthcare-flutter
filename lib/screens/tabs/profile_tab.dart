import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../features/settings/presentation/account_controller.dart';
import '../../l10n/l10n.dart';
import '../../shared/widgets/app_motion.dart';
import '../../shared/widgets/async_view.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final profile = ref.watch(patientProfileProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          Insets.sm,
          Insets.gutter,
          Insets.xxl,
        ),
        children: [
          FadeSlideIn(
            child: _ProfileHeader(
              name: session?.greetingName ?? '',
              phone: session?.phone,
              photoUrl: session?.photoUrl,
            ),
          ),
          const SizedBox(height: Insets.xl),

          // Blood group and age used to be read from SharedPreferences. They
          // are clinical data, so they live server-side in patientProfiles and
          // arrive with GET /v1/me. Age is derived from the date of birth
          // rather than stored, because a stored age is wrong within a year.
          FadeSlideIn(
            index: 1,
            child: Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: Icons.bloodtype_outlined,
                    label: l10n.profileBloodGroup,
                    value:
                        profile.value?.bloodGroup?.label ?? l10n.profileNotSet,
                    tone: context.tones.danger,
                    container: context.tones.dangerContainer,
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: _Stat(
                    icon: Icons.cake_outlined,
                    label: l10n.profileAge,
                    value: profile.value?.age?.toString() ?? l10n.profileNotSet,
                    tone: context.tones.info,
                    container: context.tones.infoContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xl),

          FadeSlideIn(
            index: 2,
            child: SectionHeader(title: l10n.settingsAccount),
          ),
          const SizedBox(height: Insets.sm),
          FadeSlideIn(
            index: 3,
            child: _MenuCard(
              items: [
                _MenuItem(
                  icon: Icons.badge_outlined,
                  label: l10n.profileEditProfile,
                  onTap: () => context.push(Routes.editProfile),
                ),
                _MenuItem(
                  icon: Icons.receipt_long_outlined,
                  label: l10n.homeQuickPrescriptions,
                  onTap: () => context.go(Routes.prescriptions),
                ),
                _MenuItem(
                  icon: Icons.shield_outlined,
                  label: l10n.recordsWhoCanSee,
                  onTap: () => context.push(Routes.sharing),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),

          FadeSlideIn(
            index: 4,
            child: _MenuCard(
              items: [
                _MenuItem(
                  icon: Icons.support_agent_outlined,
                  label: l10n.profileHelp,
                  onTap: () => context.push(Routes.supportTickets),
                ),
                _MenuItem(
                  icon: Icons.settings_outlined,
                  label: l10n.profileSettings,
                  onTap: () => context.push(Routes.settings),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),

          FadeSlideIn(
            index: 5,
            child: _SignOutTile(
              onConfirmed: () =>
                  ref.read(sessionControllerProvider.notifier).signOut(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.phone,
    required this.photoUrl,
  });

  final String name;
  final String? phone;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
          child: photoUrl != null
              ? null
              : Icon(
                  Icons.person,
                  size: 34,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
        ),
        const SizedBox(width: Insets.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (phone != null) ...[
                const SizedBox(height: Insets.xs),
                Text(
                  phone!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One clinical fact, big enough to read at arm's length.
///
/// These were two rows of a list, where the value sat right-aligned in the
/// default body size — the least prominent thing on a screen whose only real
/// content they are. A blood group is worth reading in an emergency.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.container,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final Color container;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: container, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(height: Insets.md),
            Text(
              value,
              style: theme.textTheme.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});

  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: Insets.lg + 40),
            ListTile(
              leading: Icon(items[i].icon),
              title: Text(items[i].label),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _SignOutTile extends StatelessWidget {
  const _SignOutTile({required this.onConfirmed});

  final VoidCallback onConfirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Card(
      child: ListTile(
        leading: Icon(Icons.logout, color: theme.colorScheme.error),
        title: Text(
          l10n.actionSignOut,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.w500,
          ),
        ),
        // Confirmed, because signing out of this app means re-running an OTP
        // or an OAuth consent to get back in — it is a minute of work, not a
        // toggle, and it sat one stray tap below "Settings".
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(l10n.settingsSignOutConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.actionCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.actionSignOut),
                ),
              ],
            ),
          );
          if (confirmed ?? false) onConfirmed();
        },
      ),
    );
  }
}
