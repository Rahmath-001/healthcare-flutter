import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failure.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/async_view.dart';
import '../data/operations_repository.dart';
import '../providers/operations_providers.dart';

/// Ratings awaiting moderation.
///
/// Nothing here counts towards a doctor's average until it is published, and
/// search ranks on that average — so this queue is a direct lever on which
/// doctors patients see. That is the whole reason it is moderated rather than
/// posted straight through.
class RatingModerationScreen extends ConsumerStatefulWidget {
  const RatingModerationScreen({super.key});

  @override
  ConsumerState<RatingModerationScreen> createState() =>
      _RatingModerationScreenState();
}

class _RatingModerationScreenState
    extends ConsumerState<RatingModerationScreen> {
  String? _busyId;

  Future<void> _moderate(
    PendingRating rating,
    String status, {
    bool reply = false,
  }) async {
    setState(() => _busyId = rating.id);
    try {
      final ops = ref.read(operationsRepositoryProvider);
      // Two separate decisions on purpose: a fair rating can attract a reply
      // that names a diagnosis, and hiding the patient's words to suppress the
      // doctor's would punish the wrong person.
      await (reply
          ? ops.moderateRatingReply(rating.id, status: status)
          : ops.moderateRating(rating.id, status: status));
      ref.invalidate(pendingRatingsProvider);
    } on Failure catch (f) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(f.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingRatingsProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Rating moderation', style: theme.textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(pendingRatingsProvider),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Publishing a rating changes the doctor’s average, which is '
            'what search ranks on. Hide anything abusive or identifying; '
            'remove anything that is not a genuine review. A doctor’s reply '
            'is judged separately — it is public text written by the party '
            'with the most reason to argue, and a reply naming a condition '
            'is a disclosure the patient never agreed to.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: AsyncView<List<PendingRating>>(
              value: pending,
              onRetry: () => ref.invalidate(pendingRatingsProvider),
              data: (ratings) {
                if (ratings.isEmpty) {
                  return const EmptyState(
                    icon: Icons.done_all,
                    title: 'Nothing to moderate',
                    message: 'Every rating has been reviewed.',
                  );
                }

                return ListView.separated(
                  itemCount: ratings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final r = ratings[i];
                    final busy = _busyId == r.id;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                for (var s = 1; s <= 5; s++)
                                  Icon(
                                    s <= r.stars
                                        ? Icons.star
                                        : Icons.star_border,
                                    size: 18,
                                    color: theme.colorScheme.tertiary,
                                  ),
                                const SizedBox(width: 12),
                                Text(
                                  r.doctorName,
                                  style: theme.textTheme.titleSmall,
                                ),
                                const Spacer(),
                                Text(
                                  r.editedAt != null
                                      ? 'Edited ${Fmt.relative(r.editedAt!)}'
                                      : Fmt.relative(r.createdAt),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                            if (r.comment != null && r.comment!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(r.comment!,
                                  style: theme.textTheme.bodyLarge),
                            ] else ...[
                              const SizedBox(height: 8),
                              Text(
                                'No written review.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (r.providerReply != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.reply,
                                            size: 16,
                                            color: theme
                                                .colorScheme.onSurfaceVariant),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Doctor’s reply',
                                          style: theme.textTheme.labelLarge,
                                        ),
                                        const Spacer(),
                                        Text(
                                          r.replyStatus ?? '',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(r.providerReply!,
                                        style: theme.textTheme.bodyMedium),
                                    if (r.replyNeedsModeration) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => _moderate(r, 'REMOVED',
                                                    reply: true),
                                            child: Text(
                                              'Remove reply',
                                              style: TextStyle(
                                                color: theme.colorScheme.error,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton(
                                            onPressed: busy
                                                ? null
                                                : () => _moderate(r, 'HIDDEN',
                                                    reply: true),
                                            child: const Text('Hide reply'),
                                          ),
                                          const Spacer(),
                                          FilledButton(
                                            onPressed: busy
                                                ? null
                                                : () => _moderate(
                                                    r, 'PUBLISHED',
                                                    reply: true),
                                            child: const Text('Publish reply'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => _moderate(r, 'REMOVED'),
                                  child: Text(
                                    'Remove',
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _moderate(r, 'HIDDEN'),
                                  child: const Text('Hide'),
                                ),
                                const Spacer(),
                                FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => _moderate(r, 'PUBLISHED'),
                                  child: const Text('Publish'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
