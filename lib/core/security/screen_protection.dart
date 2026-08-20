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

  static Future<void> enable() async {
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
/// Enables protection on mount and releases it on dispose, so the flag follows
/// navigation rather than being set once and forgotten — leaving FLAG_SECURE on
/// permanently would blank the whole app in the recents switcher, which users
/// read as a bug.
class ProtectedScreen extends StatefulWidget {
  const ProtectedScreen({super.key, required this.child});

  final Widget child;

  @override
  State<ProtectedScreen> createState() => _ProtectedScreenState();
}

class _ProtectedScreenState extends State<ProtectedScreen> {
  @override
  void initState() {
    super.initState();
    ScreenProtection.enable();
  }

  @override
  void dispose() {
    ScreenProtection.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
