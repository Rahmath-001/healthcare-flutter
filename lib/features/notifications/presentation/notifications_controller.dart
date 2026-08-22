import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../domain/notification.dart';

final notificationsProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  return ref.watch(notificationRepositoryProvider).list();
});

/// The badge count.
///
/// Derived from the same list the centre renders rather than fetched
/// separately, so the badge cannot disagree with what is on screen — a badge
/// that says 3 above a list showing nothing unread is the kind of small lie
/// that makes people stop trusting the badge entirely.
final unreadCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).value;
  if (notifications == null) return 0;
  return notifications.where((n) => !n.isRead).length;
});

final notificationPreferencesProvider =
    FutureProvider<NotificationPreferences>((ref) async {
  return ref.watch(notificationRepositoryProvider).preferences();
});

Future<void> markNotificationRead(WidgetRef ref, String id) async {
  await ref.read(notificationRepositoryProvider).markRead(id);
  ref.invalidate(notificationsProvider);
}

Future<void> markAllNotificationsRead(WidgetRef ref) async {
  await ref.read(notificationRepositoryProvider).markAllRead();
  ref.invalidate(notificationsProvider);
}

Future<void> saveNotificationPreferences(
  WidgetRef ref,
  NotificationPreferences preferences,
) async {
  await ref.read(notificationRepositoryProvider).updatePreferences(preferences);
  ref.invalidate(notificationPreferencesProvider);
  // The list too: on sample data a preference change decides what gets filed
  // from here on, and leaving a stale list cached makes the toggle look
  // ineffective when it is not.
  ref.invalidate(notificationsProvider);
}
