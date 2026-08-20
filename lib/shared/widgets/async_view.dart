import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failure.dart';

/// Renders an [AsyncValue] with consistent loading, error and empty states.
///
/// Every list in the app goes through this, so a network failure looks the same
/// everywhere and no screen quietly forgets to handle its error case.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
    this.padding = const EdgeInsets.all(24),
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () =>
          loading ?? const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: padding,
          child: FailureView(error: error, onRetry: onRetry),
        ),
      ),
      data: data,
    );
  }
}

/// Presents a [Failure] in the user's terms, with a retry only when retrying
/// could actually help.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failure = error is Failure ? error as Failure : null;

    final message =
        failure?.message ?? 'Something went wrong. Please try again.';
    final canRetry = onRetry != null && (failure?.isRetryable ?? true);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _iconFor(failure?.kind),
          size: 48,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (failure?.requestId != null) ...[
          const SizedBox(height: 8),
          Text(
            'Reference: ${failure!.requestId}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (canRetry) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ],
    );
  }

  static IconData _iconFor(FailureKind? kind) => switch (kind) {
        FailureKind.network => Icons.wifi_off_outlined,
        FailureKind.forbidden => Icons.lock_outline,
        FailureKind.notFound => Icons.search_off_outlined,
        FailureKind.rateLimited => Icons.hourglass_empty,
        _ => Icons.error_outline,
      };
}

/// Shared empty state, so "nothing here yet" always reads as a deliberate
/// state rather than a blank screen the app failed to fill.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Read-only star display.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.count,
    this.size = 16,
  });

  final double rating;
  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size + 2, color: Colors.amber.shade700),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: size,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );
  }
}

/// Small status pill used on appointments, records and credentials.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
