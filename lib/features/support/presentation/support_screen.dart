import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/support_ticket.dart';

final ticketsProvider = FutureProvider<List<SupportTicket>>((ref) async {
  return ref.watch(supportRepositoryProvider).listOwn();
});

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(ticketsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.supportHelpAndSupport)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const _NewTicketSheet(),
        ),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.supportNewTicket),
      ),
      body: AsyncView<List<SupportTicket>>(
        value: tickets,
        onRetry: () => ref.invalidate(ticketsProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.support_agent,
              title: context.l10n.supportNoRequests,
              message: 'If something is not working, tell us and we will help.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(ticketsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _TicketCard(ticket: list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ticket;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        title: Text(t.subject),
        subtitle: Text(
          '${t.reference} · updated ${Fmt.relative(t.updatedAt)}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: StatusChip(
          label: t.status.label,
          color:
              t.isOpen ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        children: [
          // Only the requester's own messages and public support replies are
          // ever returned; internal notes never leave the server.
          ...t.messages.map((m) => ListTile(
                dense: true,
                leading: Icon(
                  m.isFromSupport ? Icons.support_agent : Icons.person_outline,
                  size: 20,
                ),
                title: Text(m.body, style: theme.textTheme.bodyMedium),
                subtitle: Text(
                  '${m.authorName} · ${Fmt.dateTime(m.sentAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  TicketCategory _category = TicketCategory.other;
  bool _submitting = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(supportRepositoryProvider).create(
            subject: _subjectCtrl.text,
            category: _category,
            body: _bodyCtrl.text,
          );
      ref.invalidate(ticketsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.supportRequestSent)),
      );
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.supportHowCanWeHelp,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TicketCategory.values
                  .map((c) => ChoiceChip(
                        label: Text(c.label),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _subjectCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.supportTitleLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.supportWhatHappened,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please do not include medical details here. Support staff '
              'cannot see your health records.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(context.l10n.supportSendRequest),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
