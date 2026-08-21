import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tactile feedback, used sparingly and only where a tap changes state.
///
/// The rule this file exists to hold: **haptics confirm a commitment, they do
/// not decorate a tap.** A buzz on every card press is the tactile equivalent
/// of a beep on every keystroke — it stops carrying information within a
/// minute, and on Android it is loud enough that a patient in a waiting room
/// notices. So navigation gets nothing; picking a slot and completing a
/// booking get something.
///
/// Web is excluded explicitly. Flutter's web implementation of
/// `HapticFeedback` accepts the call and does nothing, so there is no crash to
/// guard against — but a `kIsWeb` check keeps the intent readable rather than
/// leaving a reader to wonder whether the browser buzzes.
abstract final class Haptics {
  /// Picking one item from a set: a date on the strip, a time in the grid.
  ///
  /// The lightest of the three. On iOS this is the selection feedback
  /// generator, which is the same tick a native picker makes.
  static Future<void> selection() async {
    if (kIsWeb) return;
    await HapticFeedback.selectionClick();
  }

  /// A commitment landed: the appointment is booked, the prescription issued.
  ///
  /// Reserved for outcomes the user would be upset to have imagined. Fires
  /// after the server confirms, never on the tap that requests it — a buzz on
  /// a request that then fails is a lie told in a channel the user cannot
  /// double-check.
  static Future<void> success() async {
    if (kIsWeb) return;
    await HapticFeedback.mediumImpact();
  }

  /// A refusal: a slot taken while it was being looked at, a hold expired.
  static Future<void> warning() async {
    if (kIsWeb) return;
    await HapticFeedback.heavyImpact();
  }
}
