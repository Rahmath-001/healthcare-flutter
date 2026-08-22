import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/formatters.dart';
import '../../shared/widgets/async_view.dart';
import '../data/operations_repository.dart';
import '../providers/operations_providers.dart';

final auditTrailProvider =
    FutureProvider.family<List<AuditEvent>, String>((ref, userId) async {
  return ref.watch(operationsRepositoryProvider).auditTrail(userId);
});

/// Who touched one patient's records.
///
/// The server has written this log since consent shipped and nothing could
/// read it back: answering "who opened my records" meant somebody with a
/// Firestore console, which is not a process you can put in a privacy notice.
///
/// Two properties this screen is built around:
///
///  * **Denials are shown, not filtered.** A doctor repeatedly trying records
///    they hold no grant for is the pattern an audit log exists to surface,
///    and a log of successes only would hide exactly the thing worth finding.
///  * **Reading it is recorded.** An audit log whose readers are not audited
///    protects everybody except from the people holding it, and a helpdesk
///    with unlogged access to who-saw-what is a surveillance tool with a
///    support ticket attached.
///
/// It takes an account id rather than a name, for the same reason this console
/// has no user search: an operator acting on an account already has its id,
/// and a box that resolves names hands a helpdesk the ability to enumerate
/// patients.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  final _controller = TextEditingController();
  String? _userId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Record access log', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Every read of one account\'s records, including refused ones. '
            'Opening this log is itself recorded against your account.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'Account id',
                    hintText: 'u-patient',
                    // Said here because an operator will look for a name box
                    // and should know why there isn't one.
                    helperText: 'There is no search by name, deliberately',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => setState(() => _userId = v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () =>
                    setState(() => _userId = _controller.text.trim()),
                child: const Text('Open log'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _userId == null || _userId!.isEmpty
                ? const EmptyState(
                    icon: Icons.history_toggle_off,
                    title: 'Enter an account id',
                    message:
                        'The id is on the account you are investigating, or '
                        'on the support ticket that brought you here.',
                  )
                : _Trail(userId: _userId!),
          ),
        ],
      ),
    );
  }
}

class _Trail extends ConsumerWidget {
  const _Trail({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trail = ref.watch(auditTrailProvider(userId));

    return AsyncView<List<AuditEvent>>(
      value: trail,
      onRetry: () => ref.invalidate(auditTrailProvider(userId)),
      data: (events) => events.isEmpty
          ? const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Nothing recorded',
              message: 'No one has read this account\'s records.',
            )
          : ListView.separated(
              itemCount: events.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _EventRow(event: events[i]),
            ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final denied = event.wasDenied;
    final accent =
        denied ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;

    return ListTile(
      leading: Icon(
        denied ? Icons.block : Icons.visibility_outlined,
        color: accent,
        size: 20,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(event.actorName, style: theme.textTheme.titleSmall),
          ),
          const SizedBox(width: 8),
          // A refusal reads as a refusal at a glance, rather than as one more
          // line in a list of reads.
          if (denied)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'REFUSED',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${event.action} · ${event.recordTitle}'
        '${event.actorRole.isEmpty ? '' : ' · ${event.actorRole}'}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        Fmt.dateTime(event.at),
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
