import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/async_view.dart';
import '../data/operations_repository.dart';
import '../providers/operations_providers.dart';
import '../router/admin_router.dart';

final operationsSummaryProvider =
    FutureProvider<OperationsSummary>((ref) async {
  return ref.watch(operationsRepositoryProvider).summary();
});

/// What is waiting, before you go looking for it.
///
/// The console had four queues and no overview, so an operator opening it had
/// no way to know which one needed them. Every figure here is a link into the
/// queue behind it — a dashboard that reports a backlog and cannot take you to
/// it makes you find it twice.
///
/// Sections are absent, not zeroed, when the operator may not see them. A
/// support agent has no business knowing how many doctors are awaiting
/// verification.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(operationsSummaryProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: AsyncView<OperationsSummary>(
        value: summary,
        onRetry: () => ref.invalidate(operationsSummaryProvider),
        data: (s) {
          if (s.isEmpty) {
            return const EmptyState(
              icon: Icons.dashboard_outlined,
              title: 'Nothing assigned to you',
              message: 'Your account has no queues attached to it.',
            );
          }

          return ListView(
            children: [
              Text('Waiting now', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Counts are live. Open a queue to act on it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  if (s.verification != null)
                    _Card(
                      label: 'Applications waiting',
                      value: '${s.verification!.pending}',
                      // The number that matters more than the count: ten filed
                      // this morning is a normal Tuesday, one filed three
                      // weeks ago is somebody who cannot earn a living.
                      caption: _waited(s.verification!.oldestWaiting),
                      alarming: _isSlow(s.verification!.oldestWaiting, 72),
                      onTap: () => context.go(AdminRoutes.queue),
                    ),
                  if (s.moderation != null)
                    _Card(
                      label: 'Ratings to moderate',
                      value: '${s.moderation!.pending}',
                      caption: _waited(s.moderation!.oldestWaiting),
                      alarming: _isSlow(s.moderation!.oldestWaiting, 72),
                      onTap: () => context.go(AdminRoutes.ratings),
                    ),
                  if (s.support != null) ...[
                    _Card(
                      label: 'Open tickets',
                      value: '${s.support!.open}',
                      caption: _waited(s.support!.oldestWaiting),
                      alarming: false,
                      onTap: () => context.go(AdminRoutes.tickets),
                    ),
                    _Card(
                      label: 'Past response target',
                      value: '${s.support!.breachingSla}',
                      caption: '24 hours to first reply',
                      alarming: s.support!.breachingSla > 0,
                      onTap: () => context.go(AdminRoutes.tickets),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'The response target is a placeholder with no contractual '
                'authority behind it. Treat it as a prompt, not a promise.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  static String _waited(Duration? d) {
    if (d == null) return 'Nothing waiting';
    if (d.inHours < 1) return 'Oldest: under an hour';
    if (d.inHours < 48) return 'Oldest: ${d.inHours} hours';
    return 'Oldest: ${d.inDays} days';
  }

  static bool _isSlow(Duration? d, int hours) =>
      d != null && d.inHours >= hours;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.label,
    required this.value,
    required this.caption,
    required this.alarming,
    required this.onTap,
  });

  final String label;
  final String value;
  final String caption;

  /// Encoded in form as well as number, so what needs attention reads at a
  /// glance rather than having to be compared against a threshold in the
  /// reader's head.
  final bool alarming;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        alarming ? theme.colorScheme.error : theme.colorScheme.primary;

    return SizedBox(
      width: 240,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(width: 3, height: 16, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label, style: theme.textTheme.labelMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(caption, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
