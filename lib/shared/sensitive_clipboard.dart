import 'dart:async';

import 'package:flutter/services.dart';

/// Copies a credential to the clipboard and takes it back again.
///
/// The MFA enrolment screen puts two things on the system clipboard: the TOTP
/// seed and the recovery codes. Both are authentication factors — the recovery
/// codes are a permanent bypass of the second factor — and the clipboard is the
/// least private place on the device. It is readable by other apps on older
/// Android, surfaced in the Android 13+ clipboard preview, and synced to other
/// machines by macOS Universal Clipboard and several Android keyboards.
///
/// Copy is still offered, because the alternative is a patient transcribing a
/// 32-character base32 seed by hand and giving up. The mitigation is to make
/// the exposure short: password managers have done exactly this for years, and
/// it is the honest trade between usability and a credential sitting in a
/// shared buffer until the next thing is copied — which may be days.
abstract final class SensitiveClipboard {
  /// How long a credential is allowed to remain on the clipboard.
  ///
  /// Long enough to switch to an authenticator app and paste; short enough that
  /// it is gone before the phone is handed to someone.
  static const window = Duration(seconds: 60);

  static Timer? _pending;

  /// Copies [value], then clears the clipboard after [window].
  ///
  /// Returns immediately; the clear is scheduled. Only one clear is ever
  /// pending — copying a second credential replaces the first one's timer
  /// rather than letting an old timer wipe the new value early.
  static Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));

    _pending?.cancel();
    _pending = Timer(window, () => _clearIfUnchanged(value));
  }

  /// Clears the clipboard only if it still holds what we put there.
  ///
  /// The comparison is the point: wiping unconditionally would destroy whatever
  /// the user copied in the meantime, which is a good way to make people
  /// distrust the app over something that has nothing to do with security.
  ///
  /// Reading our own clipboard content does not trigger iOS's "pasted from"
  /// banner — that fires for content another app placed there — so the check
  /// costs nothing visible.
  static Future<void> _clearIfUnchanged(String value) async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text != value) return;
      await Clipboard.setData(const ClipboardData(text: ''));
    } on PlatformException {
      // A clipboard we cannot read is one we should not overwrite.
    } on MissingPluginException {
      // No platform side (tests, desktop).
    }
  }

  /// Cancels a pending clear. Call from `dispose` so a timer does not outlive
  /// the screen that scheduled it.
  static void cancel() {
    _pending?.cancel();
    _pending = null;
  }
}
