import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/rating.dart';

final providerRatingsProvider = FutureProvider<List<Rating>>((ref) async {
  return ref.watch(ratingsRepositoryProvider).listForProvider();
});

Future<Rating> replyToRating(
  WidgetRef ref,
  String id, {
  required String reply,
}) async {
  final result =
      await ref.read(ratingsRepositoryProvider).reply(id, reply: reply);
  ref.invalidate(providerRatingsProvider);
  return result;
}

/// What patients said, and the doctor's right of response.
///
/// A rating is the one thing about a provider that search ranks on and that
/// the provider could not touch. An unfair one stood unanswered forever, and
/// the only recourse was asking an operator to hide something that was merely
/// unflattering — which is a worse tool, used on the wrong problem.
class ProviderRatingsScreen extends ConsumerWidget {
  const ProviderRatingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratings = ref.watch(providerRatingsProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.providerRatingsTitle)),
      body: AsyncView<List<Rating>>(
        value: ratings,
        onRetry: () => ref.invalidate(providerRatingsProvider),
        skeleton: const SkeletonList(count: 4, rows: 3),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.star_outline,
              title: l10n.providerRatingsEmpty,
              message: l10n.providerRatingsEmptyBody,
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(providerRatingsProvider.future),
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
                child: _RatingCard(rating: items[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RatingCard extends ConsumerWidget {
  const _RatingCard({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final r = rating;

    return Card(
      child: Padding(
        padding: Insets.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StarRating(rating: r.stars.toDouble()),
                const Spacer(),
                StatusChip(
                  label: r.status.label,
                  tone: switch (r.status) {
                    RatingStatus.published => Tone.success,
                    RatingStatus.pendingModeration => Tone.warning,
                    _ => Tone.neutral,
                  },
                ),
              ],
            ),
            if (r.comment != null && r.comment!.isNotEmpty) ...[
              const SizedBox(height: Insets.md),
              Text(r.comment!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: Insets.sm),
            Text(Fmt.relative(r.createdAt), style: theme.textTheme.labelSmall),
            if (r.hasReply) ...[
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
                    Text(
                      l10n.ratingReplyLabel,
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: Insets.xs),
                    Text(r.providerReply!, style: theme.textTheme.bodySmall),
                    if (!r.replyIsVisible) ...[
                      const SizedBox(height: Insets.sm),
                      // Said plainly, because a doctor who cannot see their own
                      // reply on the public listing will otherwise write it
                      // again.
                      Text(
                        l10n.ratingReplyPending,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (r.canReply) ...[
              const SizedBox(height: Insets.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _openReply(context, ref, r),
                  icon: const Icon(Icons.reply, size: 18),
                  label: Text(l10n.ratingReplyAction),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openReply(
    BuildContext context,
    WidgetRef ref,
    Rating r,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final sentMessage = context.l10n.ratingReplySent;

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReplySheet(rating: r),
    );

    if (sent ?? false) {
      messenger.showSnackBar(SnackBar(content: Text(sentMessage)));
    }
  }
}

class _ReplySheet extends ConsumerStatefulWidget {
  const _ReplySheet({required this.rating});

  final Rating rating;

  @override
  ConsumerState<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends ConsumerState<_ReplySheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);

    try {
      await replyToRating(ref, widget.rating.id, reply: _controller.text);
      Haptics.success();
      navigator.pop(true);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text(f.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
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
            Text(l10n.ratingReplyTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Insets.md),
            // Stated before the field, not after. A warning under a box someone
            // has already filled in is a warning they read while deciding
            // whether to ignore it.
            Text(l10n.ratingReplyNote, style: theme.textTheme.bodySmall),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _controller,
              maxLines: 4,
              maxLength: Rating.maxReplyLength,
              // A reply concerns a specific consultation, so the same
              // keyboard-dictionary rule as every other clinical field applies.
              // See `edit_profile_screen.dart`.
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: l10n.ratingReplyHint,
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Insets.md),
            FilledButton(
              onPressed:
                  _controller.text.trim().isEmpty || _sending ? null : _send,
              child: _sending
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Text(l10n.ratingReplySend),
            ),
          ],
        ),
      ),
    );
  }
}
