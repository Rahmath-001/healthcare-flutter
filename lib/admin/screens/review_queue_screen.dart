import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session/user_role.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/async_view.dart';
import '../data/operations_repository.dart';
import '../providers/operations_providers.dart';
import '../router/admin_router.dart';

/// Doctors waiting to be verified.
///
/// The oldest application is first, deliberately: a queue sorted by anything
/// else is a queue where somebody waits forever.
class ReviewQueueScreen extends ConsumerWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(reviewQueueProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Provider verification', style: theme.textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(reviewQueueProvider),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Every doctor here is waiting to see patients. Verification is a '
            'human decision — the register lookup is not something the system '
            'can do for you.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: AsyncView<List<ProviderApplication>>(
              value: queue,
              onRetry: () => ref.invalidate(reviewQueueProvider),
              data: (applications) {
                if (applications.isEmpty) {
                  return const EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'Nothing waiting',
                    message: 'Every submitted application has been reviewed.',
                  );
                }

                return Card(
                  child: ListView.separated(
                    itemCount: applications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = applications[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            (a.displayName ?? '?')
                                .characters
                                .first
                                .toUpperCase(),
                          ),
                        ),
                        title: Text(a.displayName ?? 'Unnamed applicant'),
                        subtitle: Text(
                          [
                            if (a.registrationNumber != null)
                              'Reg ${a.registrationNumber}',
                            if (a.email != null) a.email!,
                            if (a.phone != null) a.phone!,
                          ].join('  ·  '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StatusChip(status: a.providerStatus),
                            if (a.submittedAt != null) ...[
                              const SizedBox(width: 16),
                              Text(
                                Fmt.relative(a.submittedAt!),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => context.go(AdminRoutes.provider(a.userId)),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ProviderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Under review is somebody else's work in progress; awaiting review is
    // available. The colour difference is the whole point of showing it.
    final colour = switch (status) {
      ProviderStatus.submitted => scheme.primary,
      ProviderStatus.underReview => scheme.tertiary,
      ProviderStatus.resubmitRequested => scheme.error,
      _ => scheme.outline,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: colour, fontWeight: FontWeight.w600),
      ),
    );
  }
}
