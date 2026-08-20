import '../../../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../domain/consent.dart';
import 'consent_controller.dart';

/// "Who can see my records", plus the access log.
///
/// This is the single most important trust surface in the product and a DPDP
/// obligation: a patient must be able to see who holds access, end it in one
/// tap, and review every time a record of theirs was opened.
class SharingScreen extends ConsumerWidget {
  const SharingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.sharingHeading),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Who has access'),
              Tab(text: 'Access log'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_GrantsTab(), _AccessLogTab()],
        ),
      ),
    );
  }
}

class _GrantsTab extends ConsumerWidget {
  const _GrantsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grants = ref.watch(grantsProvider);
    final requests = ref.watch(pendingRequestsProvider);
    final theme = Theme.of(context);

    return AsyncView<List<RecordAccessGrant>>(
      value: grants,
      onRetry: () => ref.invalidate(grantsProvider),
      data: (all) {
        final active = all.where((g) => g.isActive).toList();
        final ended = all.where((g) => !g.isActive).toList();
        final pending = requests.value ?? const <RecordAccessRequest>[];

        if (active.isEmpty && ended.isEmpty && pending.isEmpty) {
          return EmptyState(
            icon: Icons.shield_outlined,
            title: context.l10n.sharingNobodyHasAccess,
            message: 'When you share records with a doctor, they will appear '
                'here and you can end that access at any time.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(grantsProvider);
            ref.invalidate(pendingRequestsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ...[
                Text(context.l10n.sharingRequestsWaiting,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...pending.map((r) => _RequestCard(request: r)),
                const SizedBox(height: 20),
              ],
              if (active.isNotEmpty) ...[
                Text(context.l10n.sharingCurrentlyShared,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...active.map((g) => _GrantCard(grant: g)),
                const SizedBox(height: 20),
              ],
              if (ended.isNotEmpty) ...[
                Text(context.l10n.sharingEnded,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...ended.map((g) => _GrantCard(grant: g)),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One live or ended grant, with a running countdown while it is live.
class _GrantCard extends ConsumerStatefulWidget {
  const _GrantCard({required this.grant});

  final RecordAccessGrant grant;

  @override
  ConsumerState<_GrantCard> createState() => _GrantCardState();
}

class _GrantCardState extends ConsumerState<_GrantCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.grant.isActive) {
      // A visible countdown is what makes "time-boxed" feel true rather than
      // merely stated.
      _ticker = Timer.periodic(
        const Duration(seconds: 30),
        (_) => mounted ? setState(() {}) : null,
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _confirmRevoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.sharingStopSharingQuestion),
        content: Text(
          '${widget.grant.providerName} will immediately lose access to your '
          'records. You can share again later if you need to.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.sharingKeepSharing),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.sharingStopSharing),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await revokeGrant(ref, widget.grant.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.sharingAccessEnded)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.grant;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.providerName, style: theme.textTheme.titleSmall),
                      Text(g.providerSpecialty,
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                StatusChip(
                  label: g.isRevoked
                      ? 'Revoked'
                      : g.isExpired
                          ? 'Expired'
                          : 'Ends in ${Fmt.countdown(g.remaining)}',
                  color: g.isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  icon: g.isActive ? Icons.timer_outlined : Icons.history,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(theme, Icons.folder_outlined, g.scopeLabel),
            _row(theme, Icons.info_outline, g.purpose.label),
            if (g.appointmentReference != null)
              _row(theme, Icons.confirmation_number_outlined,
                  'Appointment ${g.appointmentReference}'),
            _row(theme, Icons.visibility_outlined,
                'Opened ${g.usesCount} time${g.usesCount == 1 ? '' : 's'}'),
            if (g.isActive) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _confirmRevoke,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.block, size: 18),
                  label: Text(context.l10n.sharingStopSharing),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 15, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
          ],
        ),
      );
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request});

  final RecordAccessRequest request;

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    final repo = ref.read(consentRepositoryProvider);
    if (approve) {
      final duration = await showModalBottomSheet<ConsentDuration>(
        context: context,
        showDragHandle: true,
        builder: (_) => const _DurationSheet(),
      );
      if (duration == null) return;
      await repo.approveRequest(
        request.id,
        duration: duration.duration,
        scopeKind: ConsentScopeKind.allRecords,
      );
    } else {
      await repo.denyRequest(request.id);
    }

    ref.invalidate(pendingRequestsProvider);
    ref.invalidate(grantsProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Records shared' : 'Request declined'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = request;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.providerName} would like to see your records',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(r.providerSpecialty, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            if (r.message != null) ...[
              Text('"${r.message}"',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),
            ],
            Text(
              'Asked ${Fmt.relative(r.requestedAt)} · '
              'expires ${Fmt.relative(r.expiresAt)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _respond(context, ref, approve: false),
                    child: Text(context.l10n.sharingDeny),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _respond(context, ref, approve: true),
                    child: Text(context.l10n.sharingShare),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Duration picker. Every option is finite — there is no "until I revoke".
class _DurationSheet extends StatelessWidget {
  const _DurationSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(context.l10n.sharingHowLong,
                style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Access ends automatically. You can also stop it sooner.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          ...ConsentDuration.values.map((d) => ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(d.label),
                onTap: () => Navigator.of(context).pop(d),
              )),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _AccessLogTab extends ConsumerWidget {
  const _AccessLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(accessLogProvider);
    final theme = Theme.of(context);

    return AsyncView<List<RecordAccessEvent>>(
      value: log,
      onRetry: () => ref.invalidate(accessLogProvider),
      data: (events) {
        if (events.isEmpty) {
          return EmptyState(
            icon: Icons.history,
            title: context.l10n.sharingNothingToShow,
            message: 'Every time a doctor opens one of your records, it will '
                'be listed here.',
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.refresh(accessLogProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = events[i];
              final denied = e.action == AccessAction.denied;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: (denied
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary)
                      .withValues(alpha: 0.12),
                  child: Icon(
                    denied ? Icons.block : Icons.visibility_outlined,
                    size: 20,
                    color: denied
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
                title: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: e.actorName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: ' ${e.actionLabel} '),
                    TextSpan(
                      text: e.recordTitle,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ]),
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  '${Fmt.dateTime(e.at)}'
                  '${e.purpose != null ? ' · ${e.purpose!.label}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
