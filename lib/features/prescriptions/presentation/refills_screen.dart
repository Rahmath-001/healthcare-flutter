import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/providers.dart';
import '../../../core/session/user_role.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/refill_request.dart';

final refillRequestsProvider = FutureProvider<List<RefillRequest>>((ref) async {
  return ref.watch(prescriptionRepositoryProvider).refillRequests();
});

/// One list, two audiences.
///
/// A patient sees what they asked for and what came back; a doctor sees what
/// is waiting on them. The server decides which by looking at the session, so
/// there is no "whose" parameter a client could get wrong.
class RefillsScreen extends ConsumerWidget {
  const RefillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(refillRequestsProvider);
    final isProvider =
        ref.watch(currentSessionProvider)?.role == UserRole.provider;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.refillsTitle)),
      body: AsyncView<List<RefillRequest>>(
        value: requests,
        onRetry: () => ref.invalidate(refillRequestsProvider),
        skeleton: const SkeletonList(count: 3, rows: 3),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.autorenew_outlined,
              title: l10n.refillsEmpty,
              message: l10n.refillsEmptyBody,
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(refillRequestsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.lg,
                Insets.lg,
                Insets.xxl,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: Insets.md),
              itemBuilder: (_, i) => FadeSlideIn(
                key: ValueKey(items[i].id),
                index: i,
                child: RefillCard(
                  request: items[i],
                  isProvider: isProvider,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class RefillCard extends ConsumerStatefulWidget {
  const RefillCard({
    super.key,
    required this.request,
    required this.isProvider,
  });

  final RefillRequest request;
  final bool isProvider;

  @override
  ConsumerState<RefillCard> createState() => _RefillCardState();
}

class _RefillCardState extends ConsumerState<RefillCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(refillRequestsProvider);
      Haptics.success();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } on Failure catch (f) {
      Haptics.warning();
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final decision = await showModalBottomSheet<
        ({
          RefillDeclineReason reason,
          String note,
        })>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _DeclineSheet(),
    );
    if (decision == null || !mounted) return;

    final repo = ref.read(prescriptionRepositoryProvider);
    await _run(
      () => repo.declineRefill(
        widget.request.id,
        reason: decision.reason,
        note: decision.note,
      ),
      context.l10n.refillDecided,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final r = widget.request;

    return Card(
      child: Padding(
        padding: Insets.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.doctorName, style: theme.textTheme.titleSmall),
                ),
                StatusChip(
                  label: r.status.label,
                  tone: switch (r.status) {
                    RefillStatus.approved => Tone.success,
                    RefillStatus.declined => Tone.danger,
                    RefillStatus.pending => Tone.warning,
                    RefillStatus.cancelled => Tone.neutral,
                  },
                ),
              ],
            ),
            const SizedBox(height: Insets.xs),
            Text(Fmt.relative(r.requestedAt),
                style: theme.textTheme.labelSmall),

            if (r.patientNote != null) ...[
              const SizedBox(height: Insets.md),
              Text(r.patientNote!, style: theme.textTheme.bodySmall),
            ],

            // The decision, in the patient's terms. A refusal that says only
            // "declined" leaves someone unable to tell whether to book a
            // review, wait, or stop taking the medicine.
            if (r.status == RefillStatus.declined) ...[
              const SizedBox(height: Insets.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Insets.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: Radii.smAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.declineReason != null)
                      Text(
                        r.declineReason!.label,
                        style: theme.textTheme.titleSmall,
                      ),
                    if (r.decisionNote != null) ...[
                      const SizedBox(height: Insets.xs),
                      Text(r.decisionNote!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],

            if (r.status == RefillStatus.approved) ...[
              const SizedBox(height: Insets.md),
              Text(l10n.refillApproved, style: theme.textTheme.bodySmall),
            ],

            if (r.isOpen) ...[
              const SizedBox(height: Insets.md),
              if (widget.isProvider)
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : _decline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: Text(l10n.refillDecline),
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => ref
                                      .read(prescriptionRepositoryProvider)
                                      .approveRefill(r.id),
                                  l10n.refillDecided,
                                ),
                        child: Text(l10n.refillApprove),
                      ),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              () => ref
                                  .read(prescriptionRepositoryProvider)
                                  .cancelRefill(r.id),
                              l10n.refillDecided,
                            ),
                    child: Text(l10n.refillWithdraw),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The doctor's decline. Neither field is optional.
class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet();

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  RefillDeclineReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _valid => _reason != null && _note.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Insets.gutter,
          0,
          Insets.gutter,
          Insets.gutter + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.refillDeclineTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Insets.lg),

            Text(l10n.refillDeclineWhy, style: theme.textTheme.titleSmall),
            const SizedBox(height: Insets.sm),
            // A closed set, because a structured refusal can be counted and
            // audited later and a paragraph cannot — and because the category
            // is what tells the patient what to *do*.
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: RefillDeclineReason.values
                  .map((reason) => ChoiceChip(
                        label: Text(reason.label),
                        selected: _reason == reason,
                        onSelected: (_) => setState(() => _reason = reason),
                      ))
                  .toList(),
            ),

            const SizedBox(height: Insets.xl),
            Text(l10n.refillDeclineNote, style: theme.textTheme.titleSmall),
            const SizedBox(height: Insets.sm),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: RefillRequest.maxDecisionNoteLength,
              // Clinical free text about a specific patient. Same
              // keyboard-dictionary rule as everywhere else — see
              // `edit_profile_screen.dart`.
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(alignLabelWithHint: true),
            ),
            Text(
              l10n.refillDeclineNoteRequired,
              style: theme.textTheme.bodySmall,
            ),

            const SizedBox(height: Insets.lg),
            FilledButton(
              // Disabled until both are present. The server refuses a blank
              // note, so allowing the tap would only produce an error the
              // doctor has to read and then fix anyway.
              onPressed: _valid
                  ? () => Navigator.of(context).pop(
                        (reason: _reason!, note: _note.text),
                      )
                  : null,
              child: Text(l10n.refillDeclineSend),
            ),
          ],
        ),
      ),
    );
  }
}
