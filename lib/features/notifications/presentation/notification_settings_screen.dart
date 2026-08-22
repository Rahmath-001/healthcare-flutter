import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/notification.dart';
import 'notifications_controller.dart';

/// Per-kind toggles and quiet hours.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsSettings)),
      body: AsyncView<NotificationPreferences>(
        value: prefs,
        onRetry: () => ref.invalidate(notificationPreferencesProvider),
        data: (preferences) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Insets.gutter,
            Insets.lg,
            Insets.gutter,
            Insets.xxl,
          ),
          children: [
            SectionHeader(title: l10n.notificationsWhatToSend),
            const SizedBox(height: Insets.sm),
            Card(
              child: Column(
                children: [
                  for (final kind in NotificationKind.values) ...[
                    if (kind != NotificationKind.values.first)
                      const Divider(height: 1, indent: Insets.lg),
                    _KindTile(
                      kind: kind,
                      preferences: preferences,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Insets.xl),
            SectionHeader(title: l10n.notificationsQuietHours),
            const SizedBox(height: Insets.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Insets.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.notificationsQuietHoursBody,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: Insets.lg),
                    _HourRow(
                      label: l10n.notificationsQuietFrom,
                      hour: preferences.quietHours.startHour,
                      onChanged: (h) => saveNotificationPreferences(
                        ref,
                        preferences.copyWith(
                          quietHours: QuietHours(
                            startHour: h,
                            endHour: preferences.quietHours.endHour,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                    _HourRow(
                      label: l10n.notificationsQuietTo,
                      hour: preferences.quietHours.endHour,
                      onChanged: (h) => saveNotificationPreferences(
                        ref,
                        preferences.copyWith(
                          quietHours: QuietHours(
                            startHour: preferences.quietHours.startHour,
                            endHour: h,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTile extends ConsumerWidget {
  const _KindTile({required this.kind, required this.preferences});

  final NotificationKind kind;
  final NotificationPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    if (kind.isMandatory) {
      // Rendered as a fixed row, not a switch stuck on. A disabled toggle
      // invites people to try to move it; a row that was never a control says
      // what is actually true — this one always arrives.
      return ListTile(
        title: Text(_label(l10n, kind)),
        subtitle: Text(l10n.notificationsAlwaysOn),
        trailing: Icon(
          Icons.lock_outline,
          size: 18,
          color: theme.colorScheme.outline,
        ),
      );
    }

    final on = preferences.enabled.contains(kind);

    return SwitchListTile(
      title: Text(_label(l10n, kind)),
      subtitle: kind.bypassesQuietHours
          ? Text(l10n.notificationsIgnoresQuietHours)
          : null,
      value: on,
      onChanged: (next) {
        final enabled = {...preferences.enabled};
        if (next) {
          enabled.add(kind);
        } else {
          enabled.remove(kind);
        }
        saveNotificationPreferences(
          ref,
          preferences.copyWith(enabled: enabled),
        );
      },
    );
  }

  static String _label(AppLocalizations l10n, NotificationKind kind) =>
      switch (kind) {
        NotificationKind.appointmentReminder => l10n.notificationKindReminder,
        NotificationKind.appointmentChanged => l10n.notificationKindChanged,
        NotificationKind.prescriptionIssued =>
          l10n.notificationKindPrescription,
        NotificationKind.consentRequested => l10n.notificationKindConsent,
        NotificationKind.recordReady => l10n.notificationKindRecord,
        NotificationKind.ratingRequested => l10n.notificationKindRating,
        NotificationKind.accountUpdate => l10n.notificationKindAccount,
      };
}

class _HourRow extends StatelessWidget {
  const _HourRow({
    required this.label,
    required this.hour,
    required this.onChanged,
  });

  final String label;
  final int hour;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        DropdownButton<int>(
          value: hour,
          underline: const SizedBox.shrink(),
          items: [
            for (var h = 0; h < 24; h++)
              DropdownMenuItem(value: h, child: Text(_format(h))),
          ],
          onChanged: (h) {
            if (h != null) onChanged(h);
          },
        ),
      ],
    );
  }

  static String _format(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:00 ${hour < 12 ? 'AM' : 'PM'}';
  }
}
