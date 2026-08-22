import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/appointment.dart';
import '../domain/queue_position.dart';

/// Live queue position for one appointment.
///
/// Polls rather than streams: the underlying number changes when a *different*
/// patient is called in, so there is nothing on this device to react to. A
/// 30-second poll while the card is on screen is cheap and stops the instant
/// the patient navigates away — a socket held open across a waiting room full
/// of phones is not.
final queuePositionProvider = FutureProvider.autoDispose
    .family<QueuePosition, String>((ref, appointmentId) async {
  // Kept alive briefly so switching tabs and back does not refetch, but not so
  // long that a backgrounded app keeps polling.
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 30), () {
    link.close();
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  return ref.watch(appointmentRepositoryProvider).queuePosition(appointmentId);
});

/// Shown on an in-person appointment that is happening today.
///
/// Deliberately absent otherwise. A queue position for a video consultation is
/// meaningless — there is no waiting room — and one for next Tuesday is a
/// number that will be wrong by the time it matters.
class QueueCard extends ConsumerWidget {
  const QueueCard({super.key, required this.appointment});

  final Appointment appointment;

  static bool appliesTo(Appointment a) {
    if (a.mode != ConsultationMode.inPerson) return false;
    if (!a.status.isUpcoming) return false;
    final now = DateTime.now();
    return a.start.year == now.year &&
        a.start.month == now.month &&
        a.start.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tones = context.tones;
    final queue = ref.watch(queuePositionProvider(appointment.id));

    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Insets.sm),
                Text(l10n.queueTitle, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: Insets.md),
            queue.when(
              // No spinner and no error state. This card is supplementary — a
              // failure to fetch a queue position must not put a red panel on
              // an appointment screen that is otherwise fine, and the number
              // reappears on the next poll.
              loading: () => Text(
                '—',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              error: (_, __) => Text(
                '—',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              data: (q) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.isNext ? l10n.queueNext : l10n.queueAhead(q.aheadOfYou),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: q.isNext
                          ? tones.success
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (q.someoneInProgress) ...[
                    const SizedBox(height: Insets.xs),
                    Text(l10n.queueInProgress,
                        style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: Insets.sm),
                  if (!q.isCheckedIn)
                    Text(
                      l10n.queueNotCheckedIn,
                      style: theme.textTheme.bodySmall,
                    )
                  else if (q.estimatedWait != null)
                    Row(
                      children: [
                        Icon(Icons.schedule,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: Insets.xs + 2),
                        Text(
                          l10n.queueEstimate(q.estimatedWait!.inMinutes),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
