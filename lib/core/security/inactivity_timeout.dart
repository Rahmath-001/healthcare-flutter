import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../providers.dart';

/// Signs the user out after a period of no interaction.
///
/// This is the one technical safeguard the app was missing outright. Every
/// health-data regime asks for it in almost the same words — HIPAA's Security
/// Rule calls it "automatic logoff" (§164.312(a)(2)(iii)), the DPDP Act reaches
/// it through the "reasonable security safeguards" duty in §8(5) — and the
/// reason is the same everywhere: an authenticated session left open on an
/// unattended phone is an unauthenticated person's session.
///
/// It matters more here than the rule implies. Phones are commonly shared
/// within an Indian family, and the thing left on screen is a prescription or a
/// lab panel. A short window is not paranoia; it is the difference between a
/// device someone borrows and a disclosure.
///
/// **What resets the clock:** any pointer event anywhere in the app, and any
/// return to the foreground. Deliberately not the network — a background poll
/// finishing is not evidence that a human is holding the phone.
class InactivityTimeout extends ConsumerStatefulWidget {
  const InactivityTimeout({
    super.key,
    required this.child,
    this.duration = defaultDuration,
    this.now = DateTime.now,
  });

  final Widget child;
  final Duration duration;

  /// The wall clock, injectable so the background-and-return path can be
  /// tested at all.
  ///
  /// `tester.pump(duration)` advances the fake clock that drives `Timer`, but
  /// not `DateTime.now()` — so the one branch that deliberately does *not*
  /// trust a timer is the one branch a widget test cannot otherwise reach.
  /// Given that branch exists precisely because iOS suspends the process, it
  /// is the last one that should go unverified.
  @visibleForTesting
  final DateTime Function() now;

  /// 15 minutes.
  ///
  /// The common floor across health deployments, and long enough that reading
  /// a discharge summary does not expire underneath you. It is a constant
  /// rather than a `--dart-define` because a build flag that shortens a
  /// security control is a build flag that will eventually lengthen it; a
  /// per-tenant policy belongs in the session the server issues.
  static const defaultDuration = Duration(minutes: 15);

  @override
  ConsumerState<InactivityTimeout> createState() => _InactivityTimeoutState();
}

class _InactivityTimeoutState extends ConsumerState<InactivityTimeout>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _backgroundedAt;

  /// Whether a session currently exists to protect.
  ///
  /// The clock is driven by this rather than started unconditionally in
  /// `initState`. An earlier version read the session only when the timer
  /// fired, which failed open in a way that is easy to miss: at that moment the
  /// session provider can still be in its loading state — the app is restoring
  /// from the refresh token — so the read returned null, the expiry was
  /// skipped as "nobody signed in", and the timer was never re-armed. The
  /// window then stayed open for the rest of the process's life.
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_armed) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Timers do not fire reliably in the background, and on iOS the
        // process can be suspended outright — so the elapsed time is measured
        // against the wall clock on the way back in rather than trusted to a
        // timer that may never have run.
        _backgroundedAt = widget.now();
        _timer?.cancel();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            widget.now().difference(since) >= widget.duration) {
          unawaited(_expire());
        } else {
          _restart();
        }
      case AppLifecycleState.inactive:
        // The app is transiently obscured — a notification shade, a call
        // banner, the app switcher. Not a departure; leave the clock running.
        break;
    }
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(widget.duration, () => unawaited(_expire()));
  }

  void _onInteraction() {
    // Only re-arm a clock that is already running. A pointer event that
    // arrives while the app is backgrounded — it can, briefly, on Android —
    // would otherwise extend a window the user is not present for.
    if (_armed && _backgroundedAt == null) _restart();
  }

  Future<void> _expire() async {
    _timer?.cancel();
    if (!_armed) return;

    // Read before the await: the messenger is looked up through a context that
    // the sign-out redirect is about to rebuild.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = context.l10n.sessionTimedOut;

    await ref.read(sessionControllerProvider.notifier).signOut();

    // Said out loud, because an app that silently returns to its sign-in
    // screen reads as a crash or a bug, and the user's next move is to
    // distrust it with the thing it just protected.
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Watching the session is what makes the provider warm: by the time the
    // timer can fire, this widget has already rebuilt for the session it is
    // protecting. Signing out cancels the clock rather than leaving it to
    // fire against nobody.
    final signedIn = ref.watch(currentSessionProvider) != null;

    if (signedIn != _armed) {
      _armed = signedIn;
      // Deferred: mutating timers during build is how you get a setState
      // during build on the next expiry.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_armed) {
          _restart();
        } else {
          _timer?.cancel();
          _backgroundedAt = null;
        }
      });
    }

    return Listener(
      // Listener, not GestureDetector: this must observe every pointer without
      // entering the gesture arena, or it would compete with the scrolls and
      // taps of every screen underneath it.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onInteraction(),
      onPointerSignal: (_) => _onInteraction(),
      child: widget.child,
    );
  }
}
