import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failure.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../l10n/l10n.dart';
import 'app_motion.dart';
import 'skeleton.dart';

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
    this.skeleton,
    this.padding = const EdgeInsets.all(Insets.xl),
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  /// A custom loading widget. Prefer [skeleton].
  final Widget? loading;

  /// A placeholder shaped like the content that is coming — see
  /// `SkeletonList`. Preferred over a spinner on anything list-shaped: it holds
  /// the layout still, so the page does not jump under the user's thumb the
  /// moment data lands.
  final Widget? skeleton;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.fast),
      // Cross-fade only. Sliding or scaling between a skeleton and the real
      // list draws the eye to the swap rather than to the content that just
      // arrived, and the two children are the same shape anyway.
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      child: value.when(
        skipLoadingOnRefresh: true,
        loading: () => KeyedSubtree(
          key: const ValueKey('async-loading'),
          // Held back briefly — see `DelayedLoading`. A cached list resolves
          // faster than the placeholder is worth showing, and a skeleton that
          // flashes for 60ms reads as a rendering fault.
          child: DelayedLoading(
            child: skeleton ??
                loading ??
                const Center(child: CircularProgressIndicator()),
          ),
        ),
        error: (error, _) => KeyedSubtree(
          key: const ValueKey('async-error'),
          child: Center(
            child: SingleChildScrollView(
              padding: padding,
              child: FailureView(error: error, onRetry: onRetry),
            ),
          ),
        ),
        data: (value) => KeyedSubtree(
          key: const ValueKey('async-data'),
          child: data(value),
        ),
      ),
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
    final tones = context.tones;
    final failure = error is Failure ? error as Failure : null;

    final message = failure?.message ?? context.l10n.errorGeneric;
    final canRetry = onRetry != null && (failure?.isRetryable ?? true);

    // A lost connection is not a fault, and painting it in error red tells the
    // user something is broken when the fix is to walk to a window.
    final isOffline = failure?.kind == FailureKind.network;
    final accent = isOffline ? tones.warning : tones.danger;
    final accentContainer =
        isOffline ? tones.warningContainer : tones.dangerContainer;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: accentContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(_iconFor(failure?.kind), size: 32, color: accent),
        ),
        const SizedBox(height: Insets.gutter),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (failure?.requestId != null) ...[
          const SizedBox(height: Insets.sm),
          // Support asks for this code, so it has to be readable and
          // selectable — a reference nobody can copy is not a reference.
          SelectableText(
            'Ref ${failure!.requestId}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
        if (canRetry) ...[
          const SizedBox(height: Insets.xl),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 20),
            label: Text(context.l10n.actionRetry),
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
      child: SingleChildScrollView(
        // Scrollable so the state survives a landscape phone with the keyboard
        // up, where the column is taller than the viewport.
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.xxl,
          vertical: Insets.xl,
        ),
        child: FadeSlideIn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.gutter),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: Insets.sm),
                ConstrainedBox(
                  // Empty-state copy that runs the full width of a tablet is
                  // one long line the eye cannot track back from.
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: Insets.xl),
                action!,
              ],
            ],
          ),
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

    return Semantics(
      // Otherwise a screen reader announces "star, 4.6, (128)" as three
      // unrelated fragments and the number has no unit.
      label: count == null
          ? '${rating.toStringAsFixed(1)} out of 5'
          : '${rating.toStringAsFixed(1)} out of 5, $count ratings',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: size + 2,
            color: context.tones.warning,
          ),
          const SizedBox(width: Insets.xs),
          Text(
            rating.toStringAsFixed(1),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: size,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: Insets.xs),
            Text(
              '($count)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a status *means*, rather than what colour someone picked for it.
///
/// Screens used to reach for `colorScheme.primary` for anything good and
/// `colorScheme.error` for anything bad, which left "completed", "confirmed"
/// and "the primary action here" all rendered in the same teal, and a merely
/// pending review looking like a failure.
enum Tone {
  /// Confirmed, approved, completed, verified, active grant.
  success,

  /// Waiting on something: under review, scanning, expiring soon.
  warning,

  /// Cancelled, rejected, revoked, suspended.
  danger,

  /// Factual emphasis with no verdict attached.
  info,

  /// Over and done with — history, not a state to act on.
  neutral,

  /// The product's own colour. For badges about the app, not about a record.
  brand,
}

extension ToneColors on Tone {
  Color foreground(BuildContext context) {
    final tones = context.tones;
    return switch (this) {
      Tone.success => tones.success,
      Tone.warning => tones.warning,
      Tone.danger => tones.danger,
      Tone.info => tones.info,
      Tone.neutral => tones.neutral,
      Tone.brand => Theme.of(context).colorScheme.primary,
    };
  }

  Color container(BuildContext context) {
    final tones = context.tones;
    return switch (this) {
      Tone.success => tones.successContainer,
      Tone.warning => tones.warningContainer,
      Tone.danger => tones.dangerContainer,
      Tone.info => tones.infoContainer,
      Tone.neutral => tones.neutralContainer,
      Tone.brand => Theme.of(context).colorScheme.primaryContainer,
    };
  }
}

/// Small status pill used on appointments, records and credentials.
///
/// Prefer [tone] over [color]: a tone carries a meaning and picks a foreground
/// and background that are contrast-checked together in both brightnesses,
/// where a raw colour at 12% alpha is only ever checked in whichever mode the
/// author happened to have open.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone,
    this.color,
    this.icon,
  }) : assert(tone != null || color != null, 'Pass a tone or a colour');

  final String label;
  final Tone? tone;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = tone?.foreground(context) ?? color!;
    final bg = tone?.container(context) ?? color!.withValues(alpha: 0.12);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? Insets.md : Insets.sm + 2,
        vertical: Insets.xs + 1,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: Radii.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: Insets.xs + 1),
          ],
          // Flexible, because a chip sitting in a card row inherits that
          // row's width: a long status ("Awaiting resubmission") otherwise
          // overflows the card rather than shortening itself.
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                letterSpacing: 0.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The label above a group of content, optionally with one action beside it.
///
/// Exists so the gap above a section, the weight of its label and the position
/// of its "see all" are decided once. They were previously decided per screen,
/// which is why Home, Records and Sharing each introduced their sections
/// differently.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
