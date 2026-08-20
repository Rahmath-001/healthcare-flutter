import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/failure.dart';
import '../../features/support/domain/support_ticket.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/async_view.dart';
import '../admin_app.dart';
import '../providers/operations_providers.dart';
import '../router/admin_router.dart';

/// One ticket, and the reply.
class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<SupportTicketScreen> createState() =>
      _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(operationsRepositoryProvider)
          .replyToTicket(widget.ticketId, body);
      _reply.clear();
      ref.invalidate(ticketProvider(widget.ticketId));
      ref.invalidate(ticketQueueProvider);
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(TicketStatus status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(operationsRepositoryProvider)
          .setTicketStatus(widget.ticketId, status);
      ref.invalidate(ticketProvider(widget.ticketId));
      ref.invalidate(ticketQueueProvider);
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider(widget.ticketId));
    final scopes = ref.watch(operatorScopesProvider);
    final theme = Theme.of(context);

    return AsyncView<SupportTicket>(
      value: ticket,
      onRetry: () => ref.invalidate(ticketProvider(widget.ticketId)),
      data: (t) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to queue',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go(AdminRoutes.tickets),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.subject, style: theme.textTheme.titleLarge),
                      Text(
                        '${t.reference}  ·  ${t.category.label}  ·  '
                        '${t.status.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (scopes.canEscalateTickets &&
                    t.status != TicketStatus.escalated)
                  TextButton.icon(
                    onPressed:
                        _busy ? null : () => _setStatus(TicketStatus.escalated),
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    label: const Text('Escalate'),
                  ),
                const SizedBox(width: 8),
                if (t.status != TicketStatus.closed)
                  OutlinedButton(
                    onPressed:
                        _busy ? null : () => _setStatus(TicketStatus.closed),
                    child: const Text('Close'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: t.messages.length,
                  itemBuilder: (_, i) => _Message(message: t.messages[i]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _reply,
                    maxLines: 4,
                    minLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reply',
                      alignLabelWithHint: true,
                      helperText:
                          'The person who opened this ticket sees exactly this.',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final TicketMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromSupport = message.isFromSupport;

    return Align(
      alignment: fromSupport ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          color: fromSupport
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message.authorName,
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Fmt.relative(message.sentAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(message.body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
