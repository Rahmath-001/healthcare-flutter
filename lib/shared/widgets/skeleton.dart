import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'app_motion.dart';

/// A loading placeholder shaped like the content that is coming.
///
/// The app used to answer every pending list with a centred
/// `CircularProgressIndicator`. A spinner says only "wait"; it moves the whole
/// layout the instant data lands, so the user's thumb is already travelling
/// toward a button that is no longer there. A skeleton keeps the page still and
/// tells them what shape the answer will be.
///
/// Theme-aware on purpose. The previous shimmer hard-coded `Colors.grey[300]`
/// against `Colors.grey[100]`, which in dark mode flashed near-white blocks on
/// a near-black page on every load.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = Radii.smAll,
    this.shape = BoxShape.rectangle,
  });

  /// A text line. The default width is deliberately short of the full row —
  /// a full-width bar reads as a filled field rather than as pending text.
  factory Skeleton.line({double width = 140, double height = 12}) =>
      Skeleton(width: width, height: height, borderRadius: Radii.smAll);

  /// An avatar.
  factory Skeleton.circle({double radius = 24}) => Skeleton(
        width: radius * 2,
        height: radius * 2,
        shape: BoxShape.circle,
      );

  /// A block: an image, a chart, a card body.
  factory Skeleton.rect({
    double width = double.infinity,
    double height = 48,
    BorderRadius borderRadius = Radii.mdAll,
  }) =>
      Skeleton(width: width, height: height, borderRadius: borderRadius);

  final double width;
  final double height;
  final BorderRadius borderRadius;
  final BoxShape shape;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The sweep is the one repeating animation the app keeps, because it is
    // reporting status rather than decorating. With "reduce motion" on it stops
    // and the block renders flat — still a placeholder, just a silent one.
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHigh;
    final highlight = Color.alphaBlend(
      scheme.surface.withValues(alpha: 0.75),
      scheme.surfaceContainerHighest,
    );

    final decoration = BoxDecoration(
      color: base,
      shape: widget.shape,
      borderRadius:
          widget.shape == BoxShape.circle ? null : widget.borderRadius,
    );

    if (Motion.reduced(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: decoration,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // The sweep runs from off-screen left to off-screen right, so the
        // gradient never sits parked over the block between cycles.
        final t = _controller.value * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: decoration.copyWith(
            gradient: LinearGradient(
              begin: Alignment(t - 0.6, 0),
              end: Alignment(t + 0.6, 0),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Holds a placeholder back until the wait is long enough to be worth showing.
///
/// A skeleton that appears and vanishes inside 80ms is worse than no skeleton:
/// the user sees a flash of grey bars where their data was about to be, which
/// reads as a glitch rather than as loading. Cached responses and the fixture
/// backend both resolve well inside that window, so making loading *more*
/// visible — which is what skeletons do — also made the fast path worse.
///
/// Below [delay] this renders nothing at all and takes no space, so the layout
/// does not shift when the placeholder does arrive.
class DelayedLoading extends StatefulWidget {
  const DelayedLoading({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 160),
  });

  final Widget child;

  /// 160ms — under the ~200ms most people register as "instant", so a fast
  /// response never shows a placeholder at all, and a slow one is only
  /// 160ms late to admit it.
  final Duration delay;

  @override
  State<DelayedLoading> createState() => _DelayedLoadingState();
}

class _DelayedLoadingState extends State<DelayedLoading> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    // `FadeSlideIn`, not `AnimatedOpacity`: the child mounts at this moment, so
    // an implicit animation has no previous value to animate from and would
    // simply paint at full opacity. Zero offset — a placeholder that slides in
    // is drawing attention to the wait rather than to the content.
    return FadeSlideIn(
      offset: 0,
      duration: Motion.fast,
      child: widget.child,
    );
  }
}

/// Placeholder list shaped like the app's cards.
///
/// [rows] controls how many detail lines each card shows; the appointment and
/// doctor cards are three-line, the record tiles two.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 4,
    this.rows = 3,
    this.leadingAvatar = true,
    this.padding = const EdgeInsets.fromLTRB(
      Insets.lg,
      Insets.lg,
      Insets.lg,
      Insets.fabSafeBottom,
    ),
  });

  final int count;
  final int rows;
  final bool leadingAvatar;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      // Nothing here is interactive and the real list will replace it within a
      // second; letting the user fling a fake list is worse than freezing it.
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: Insets.md),
      itemBuilder: (_, __) => _SkeletonCard(
        rows: rows,
        leadingAvatar: leadingAvatar,
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.rows, required this.leadingAvatar});

  final int rows;
  final bool leadingAvatar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: Insets.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leadingAvatar) ...[
              Skeleton.circle(radius: 22),
              const SizedBox(width: Insets.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton.line(width: 168, height: 14),
                  for (var i = 0; i < rows - 1; i++) ...[
                    const SizedBox(height: Insets.sm + 2),
                    // Each line a little shorter than the one above, the way
                    // real metadata is. Equal-length bars read as a table.
                    Skeleton.line(width: 210.0 - i * 46, height: 11),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
