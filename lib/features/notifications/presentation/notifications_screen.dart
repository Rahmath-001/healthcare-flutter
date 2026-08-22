import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/notification.dart';
import 'notifications_controller.dart';

/// The notification centre.
///
/// Deliberately **not** wrapped in `ProtectedScreen`. Nothing here is clinical:
/// a notification title and body are already visible on a lock screen, so
/// blocking screenshots of the same words inside the app would be theatre. The
/// screens these link *to* are protected, which is where the detail lives.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
        actions: [
          IconButton(
            tooltip: l10n.notificationsSettings,
            icon: const Icon(Icons.tune),
            onPressed: () => context.push(Routes.notificationSettings),
          ),
          if (unread > 0)
            TextButton(
              onPressed: () => markAllNotificationsRead(ref),
              child: Text(l10n.notificationsMarkAllRead),
            ),
        ],
      ),
      body: AsyncView<List<AppNotification>>(
        value: notifications,
        onRetry: () => ref.invalidate(notificationsProvider),
        skeleton: const SkeletonList(count: 5, rows: 2),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_none_outlined,
              title: l10n.notificationsEmpty,
              message: l10n.notificationsEmptyBody,
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(notificationsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.lg,
                Insets.lg,
                Insets.xxl,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: Insets.md - 2),
              itemBuilder: (_, i) => FadeSlideIn(
                key: ValueKey(items[i].id),
                index: i,
                child: _NotificationTile(notification: items[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final n = notification;
    final tone = _toneFor(context, n.kind);

    return PressableScale(
      child: Card(
        // An unread notification gets a tinted surface rather than only a dot.
        // A 8px dot is the entire difference between read and unread otherwise,
        // and it is invisible at arm's length.
        color: n.isRead ? null : theme.colorScheme.primaryContainer,
        child: InkWell(
          onTap: () => _open(context, ref, n),
          child: Padding(
            padding: const EdgeInsets.all(Insets.md + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tone.container,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconFor(n.kind), size: 20, color: tone.fg),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight:
                              n.isRead ? FontWeight.w600 : FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Insets.xs),
                      Text(
                        Fmt.relative(n.createdAt),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                if (!n.isRead) ...[
                  const SizedBox(width: Insets.sm),
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: Insets.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification n,
  ) async {
    final router = GoRouter.of(context);

    if (!n.isRead) {
      // Marked read on tap rather than on render. A notification that clears
      // itself because the list scrolled past it is a notification the user
      // never saw and can no longer find.
      await markNotificationRead(ref, n.id);
    }

    final target = routeForNotification(n);
    if (target != null) router.push(target);
  }

  static ({Color fg, Color container}) _toneFor(
    BuildContext context,
    NotificationKind kind,
  ) {
    final tones = context.tones;
    return switch (kind) {
      NotificationKind.appointmentChanged => (
          fg: tones.danger,
          container: tones.dangerContainer
        ),
      NotificationKind.appointmentReminder => (
          fg: tones.info,
          container: tones.infoContainer
        ),
      NotificationKind.prescriptionIssued => (
          fg: tones.success,
          container: tones.successContainer
        ),
      NotificationKind.consentRequested => (
          fg: tones.warning,
          container: tones.warningContainer
        ),
      _ => (fg: tones.neutral, container: tones.neutralContainer),
    };
  }

  static IconData _iconFor(NotificationKind kind) => switch (kind) {
        NotificationKind.appointmentReminder => Icons.event_outlined,
        NotificationKind.appointmentChanged => Icons.event_busy_outlined,
        NotificationKind.prescriptionIssued => Icons.receipt_long_outlined,
        NotificationKind.consentRequested => Icons.shield_outlined,
        NotificationKind.recordReady => Icons.folder_open_outlined,
        NotificationKind.ratingRequested => Icons.star_outline,
        NotificationKind.accountUpdate => Icons.info_outline,
      };
}

/// Where a notification leads.
///
/// One function, used by both the tile and the push-tap handler, so a
/// notification opened from the lock screen and the same one opened from the
/// centre land in the same place. Two implementations of this is how they
/// diverge.
///
/// Returns null when there is nothing specific to open — the notification has
/// then already done its job by being read.
String? routeForNotification(AppNotification n) {
  final id = n.targetId;
  return switch (n.kind) {
    NotificationKind.appointmentReminder ||
    NotificationKind.appointmentChanged =>
      id == null
          ? Routes.patientAppointments
          : '${Routes.patientAppointments}/$id',
    NotificationKind.prescriptionIssued => Routes.prescriptions,
    NotificationKind.consentRequested => Routes.sharing,
    NotificationKind.recordReady => Routes.patientRecords,
    NotificationKind.ratingRequested => id == null ? null : '/patient/rate/$id',
    NotificationKind.accountUpdate => null,
  };
}
