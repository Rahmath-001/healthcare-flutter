import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/support/domain/support_ticket.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/async_view.dart';
import '../data/operations_repository.dart';
import '../providers/operations_providers.dart';
import '../router/admin_router.dart';

/// The support queue.
///
/// Note what is not here and never should be: a panel showing the ticket
/// author's appointments, records or prescriptions. Support staff hold no
/// consent grant, and a "customer context" sidebar is the fastest way to turn a
/// helpdesk into an unlogged route into a patient's medical history.
class SupportQueueScreen extends ConsumerWidget {
  const SupportQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(ticketQueueProvider);
    final filter = ref.watch(ticketFilterProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Support', style: theme.textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(ticketQueueProvider),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<TicketStatus?>(
            segments: const [
              ButtonSegment(value: TicketStatus.open, label: Text('Open')),
              ButtonSegment(
                value: TicketStatus.assigned,
                label: Text('Assigned'),
              ),
              ButtonSegment(
                value: TicketStatus.escalated,
                label: Text('Escalated'),
              ),
              ButtonSegment(value: null, label: Text('All')),
            ],
            selected: {filter},
            onSelectionChanged: (s) =>
                ref.read(ticketFilterProvider.notifier).set(s.first),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: AsyncView<List<QueuedTicket>>(
              value: tickets,
              onRetry: () => ref.invalidate(ticketQueueProvider),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Nothing here',
                    message: 'No tickets match this filter.',
                  );
                }

                return Card(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = items[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(t.subject),
                        subtitle: Text(
                          '${t.reference}  ·  ${t.category.label}  ·  '
                          '${t.messageCount} message'
                          '${t.messageCount == 1 ? '' : 's'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.status.label),
                            const SizedBox(width: 16),
                            Text(
                              Fmt.relative(t.updatedAt),
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => context.go(AdminRoutes.ticket(t.id)),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
