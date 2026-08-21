import 'package:flutter/material.dart';

/// The measurements every screen is built from.
///
/// Hand-picked numbers scattered across 26 screens are how an interface stops
/// looking like one product. Everything here is a multiple of 4, so vertical
/// rhythm survives being edited by someone who has not read this file.
abstract final class Insets {
  /// 4 — hairline gaps inside a chip or between an icon and its label.
  static const double xs = 4;

  /// 8 — related elements in the same row.
  static const double sm = 8;

  /// 12 — between cards in a list.
  static const double md = 12;

  /// 16 — the inside of a card, and the default gutter on a dense screen.
  static const double lg = 16;

  /// 20 — the screen gutter. Wider than the card padding on purpose: content
  /// that starts where the card starts reads as if the card is missing.
  static const double gutter = 20;

  /// 24 — between sections of one screen.
  static const double xl = 24;

  /// 32 — above a section that begins a new idea.
  static const double xxl = 32;

  /// Bottom padding for a scrolling list that sits under a FAB. 88 = 56 (FAB)
  /// + 16 (its margin) + 16 (breathing room), so the last row is never
  /// unreachable behind it.
  static const double fabSafeBottom = 88;

  static const EdgeInsets screen = EdgeInsets.all(gutter);
  static const EdgeInsets card = EdgeInsets.all(lg);
  static const EdgeInsets listH = EdgeInsets.symmetric(horizontal: lg);
}

/// Corner radii. Three steps only — a fourth would be a decision nobody can
/// justify at review time.
abstract final class Radii {
  /// 8 — chips, thumbnails, input fields.
  static const double sm = 8;

  /// 16 — cards, sheets, dialogs. The app's signature corner.
  static const double md = 16;

  /// 24 — full-bleed bottom sheets and the hero card on Home.
  static const double lg = 24;

  /// Pills: buttons and status chips.
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// One motion language for the whole app.
///
/// Durations are deliberately short. Anything over ~250ms on a control the user
/// tapped stops reading as feedback and starts reading as lag; the longer values
/// here are for reveals the user is not waiting on.
abstract final class Motion {
  /// 120ms — pressed/hover states, ripples, chip selection.
  static const Duration instant = Duration(milliseconds: 120);

  /// 180ms — the default. State swaps, expands, colour changes.
  static const Duration fast = Duration(milliseconds: 180);

  /// 240ms — page transitions and sheet entrances.
  static const Duration normal = Duration(milliseconds: 240);

  /// 360ms — first-run content reveals, which nobody is blocked on.
  static const Duration slow = Duration(milliseconds: 360);

  /// Delay between siblings in a staggered reveal. Small groups only: at 8+
  /// items a stagger stops feeling considered and starts feeling slow, which
  /// is why [staggerCap] exists.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Past this index every remaining item animates together.
  static const int staggerCap = 6;

  /// Decelerating — for things entering the screen.
  static const Curve enter = Curves.easeOutCubic;

  /// Accelerating — for things leaving it.
  static const Curve exit = Curves.easeInCubic;

  /// Symmetric — for something moving between two on-screen positions.
  static const Curve standard = Curves.easeInOutCubic;

  /// A single overshoot, used only on confirmation moments (booking done).
  /// Never on anything the user triggers repeatedly.
  static const Curve emphasised = Curves.easeOutBack;

  /// Honours the OS "reduce motion" switch.
  ///
  /// iOS Settings → Accessibility → Motion and Android's "Remove animations"
  /// both surface here. Vestibular disorders make sliding content genuinely
  /// unpleasant, so every animated widget in `shared/widgets` checks this and
  /// falls back to an instant cut rather than a slower version of the same
  /// movement.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when the user has asked for less motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Elevation, expressed as the M3 surface-tint levels rather than shadows.
///
/// Material 3 conveys height with tonal surfaces; stacking real shadows on top
/// of that reads as heavy in light mode and does nothing at all in dark, where
/// a shadow on a near-black background is invisible.
abstract final class Elevations {
  static const double flat = 0;
  static const double card = 0;
  static const double raised = 1;
  static const double sheet = 3;
  static const double dialog = 3;
}

/// Layout limits.
abstract final class Breakpoints {
  /// Above this a phone layout is stretched rather than used. Forms and
  /// single-column lists are centred at this width instead of running edge to
  /// edge on a tablet or on the web build.
  static const double readableWidth = 560;

  /// Below this the two-column quick-action grid becomes one column.
  static const double compact = 360;
}
