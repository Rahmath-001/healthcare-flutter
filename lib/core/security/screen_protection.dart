import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots and screen recording while a PHI screen is visible.
///
/// On Android this sets `FLAG_SECURE`, which also blanks the app in the recent-
/// apps switcher and blocks most screen-recording apps. iOS has no equivalent
/// flag; the platform side blurs the window on resign-active instead.
///
/// This matters more in India than the feature list suggests: phones are
/// commonly shared within a family, and a screenshot of a mental-health
/// prescription or an HIV panel sitting in the gallery is a permanent
/// disclosure the patient never agreed to.
///
/// It is a deterrent, not a guarantee — a second phone photographing the screen
/// defeats it. The controls that actually matter are the time-boxed consent
/// grants and the access log.
abstract final class ScreenProtection {
  static const _channel = MethodChannel('in.midoctor.app/screen_protection');

  /// Debug-only escape hatch, so a manual test pass can screenshot the PHI
  /// screens it is checking. `kDebugMode` gates it, so a release build ignores
  /// the define entirely and FLAG_SECURE is never optional in shipped code.
  static const _disabled =
      bool.fromEnvironment('DISABLE_SCREEN_PROTECTION') && kDebugMode;

  /// How many visible [ProtectedScreen]s currently want protection.
  ///
  /// Reference-counted rather than a boolean, because protected screens nest:
  /// opening a record detail over the Records tab means two of them are visible
  /// at once, and popping the detail must not switch `FLAG_SECURE` off while
  /// the list underneath is still on screen.
  static int _holders = 0;

  @visibleForTesting
  static int get holders => _holders;

  @visibleForTesting
  static void resetForTest() => _holders = 0;

  /// Claims protection. Only the first claim reaches the platform.
  static Future<void> acquire() async {
    _holders++;
    if (_holders != 1) return;
    await enable();
  }

  /// Releases one claim. Only the last release reaches the platform.
  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders != 0) return;
    await disable();
  }

  static Future<void> enable() async {
    if (_disabled) return;
    try {
      await _channel.invokeMethod<void>('enable');
    } on PlatformException {
      // Never let a missing platform implementation stop a patient reading
      // their own record.
    } on MissingPluginException {
      // Platform side not wired (tests, desktop).
    }
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod<void>('disable');
    } on PlatformException {
      // Ignored: see enable().
    } on MissingPluginException {
      // Ignored: see enable().
    }
  }
}

/// Wraps a route whose content is protected health information.
///
/// Protection follows **visibility**, not mount. That distinction is the whole
/// point of this class, and getting it wrong was a real defect: the Records and
/// Prescriptions tabs are branches of a `StatefulShellRoute.indexedStack`,
/// which keeps every visited branch alive forever. Enabling on `initState` and
/// disabling on `dispose` therefore meant that once a patient opened Records,
/// `FLAG_SECURE` stayed on for the rest of the process — the app blanked in the
/// recents switcher from then on, which reads as a bug, and the release call
/// never ran at all.
///
/// The signal is `TickerMode`: go_router wraps inactive branches in
/// `Offstage(offstage: true, child: TickerMode(enabled: false, ...))`, so an
/// inactive tab is exactly a disabled ticker. That also makes this correct for
/// ordinary pushed routes, which stay ticking underneath a pushed page — a
/// record list under an open record detail is still protected, and still
/// protected after the detail pops.
class ProtectedScreen extends StatefulWidget {
  const ProtectedScreen({super.key, required this.child});

  final Widget child;

  @override
  State<ProtectedScreen> createState() => _ProtectedScreenState();
}

class _ProtectedScreenState extends State<ProtectedScreen> {
  bool _holding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reading TickerMode here registers the dependency, so this method runs
    // again the moment the branch is switched away from or back to.
    _sync(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _sync(false);
    super.dispose();
  }

  void _sync(bool wanted) {
    if (wanted == _holding) return;
    _holding = wanted;
    if (wanted) {
      ScreenProtection.acquire();
    } else {
      ScreenProtection.release();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
