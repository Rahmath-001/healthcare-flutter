import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// The app's two motion primitives.
///
/// Both are deliberately small. Motion here exists to explain where something
/// came from and to confirm a tap landed — not to decorate. Everything animates
/// `opacity` and `transform` only, so nothing triggers a relayout mid-flight,
/// and everything collapses to an instant cut when the OS asks for reduced
/// motion.

/// Fades and lifts its child into place once, on first build.
///
/// [index] staggers siblings in a list. The delay is capped at
/// [Motion.staggerCap] so a 40-row list does not take two seconds to finish
/// arriving — past the cap everything remaining lands together.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = Motion.slow,
    this.offset = 12,
  });

  final Widget child;
  final int index;
  final Duration duration;

  /// Vertical travel in logical pixels. Small on purpose: content that flies
  /// half a screen draws attention to the animation rather than the content.
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Motion.enter,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (Motion.reduced(context)) {
      _controller.value = 1;
      return;
    }

    final steps = widget.index.clamp(0, Motion.staggerCap);
    final delay = Motion.stagger * steps;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        // The route can be popped inside the stagger window — a fast
        // back-tap on a long list is enough — and forwarding a disposed
        // controller throws.
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _fade.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Shrinks slightly while pressed.
///
/// Wraps cards and tiles whose tap target is the whole surface. A ripple alone
/// is easy to miss on a large card — it starts under the thumb, which is the
/// one part of the card the user cannot see — whereas the whole card moving is
/// unambiguous even when it is covered.
///
/// This does not add a gesture: [onTap] still belongs to the `InkWell` inside,
/// so ripple, focus, keyboard activation and semantics all keep working.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.scale = 0.98,
    this.enabled = true,
  });

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Listener rather than GestureDetector: a competing gesture recogniser
      // (the scroll view this usually lives in) can win the arena and leave a
      // GestureDetector's onTapUp unfired, which would strand the card at 0.98.
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? widget.scale : 1,
        duration: Motion.of(context, Motion.instant),
        curve: Motion.standard,
        child: widget.child,
      ),
    );
  }
}
