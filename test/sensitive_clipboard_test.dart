import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/shared/sensitive_clipboard.dart';

/// Clipboard expiry for authentication credentials.
///
/// The TOTP seed and the recovery codes are the two values in this app that
/// grant access on their own. They go to the clipboard because the alternative
/// is transcribing base32 by hand; the whole safety of that decision rests on
/// them not staying there — which is a behaviour, and therefore something to
/// assert rather than trust.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return clipboard == null
              ? null
              : <String, Object?>{'text': clipboard};
      }
      return null;
    });
  });

  tearDown(() {
    SensitiveClipboard.cancel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('the credential is on the clipboard immediately', (tester) async {
    await SensitiveClipboard.copy('JBSWY3DPEHPK3PXP');
    expect(clipboard, 'JBSWY3DPEHPK3PXP');

    // Cancelled inside the test body, not in tearDown: the binding asserts on
    // pending timers before tearDown gets a turn.
    SensitiveClipboard.cancel();
  });

  testWidgets('and gone once the window passes', (tester) async {
    await SensitiveClipboard.copy('JBSWY3DPEHPK3PXP');

    await tester.pump(SensitiveClipboard.window - const Duration(seconds: 1));
    expect(clipboard, 'JBSWY3DPEHPK3PXP', reason: 'still inside the window');

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(clipboard, isEmpty);
  });

  testWidgets('something the user copied afterwards is left alone',
      (tester) async {
    await SensitiveClipboard.copy('JBSWY3DPEHPK3PXP');

    // The user copies a phone number while the timer is still pending.
    clipboard = '+919876543210';

    await tester.pump(SensitiveClipboard.window + const Duration(seconds: 1));
    await tester.pump();

    // Wiping this would be a good way to make someone distrust the app over
    // something with nothing to do with security.
    expect(clipboard, '+919876543210');
  });

  testWidgets('copying a second credential does not expire it early',
      (tester) async {
    await SensitiveClipboard.copy('first');
    await tester.pump(SensitiveClipboard.window - const Duration(seconds: 5));

    await SensitiveClipboard.copy('second');
    // The first copy's timer would fire about now. It must have been cancelled,
    // or the second credential is wiped five seconds after being copied.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(clipboard, 'second');

    await tester.pump(SensitiveClipboard.window);
    await tester.pump();
    expect(clipboard, isEmpty);
  });

  testWidgets('cancel stops a pending clear', (tester) async {
    await SensitiveClipboard.copy('secret');
    SensitiveClipboard.cancel();

    await tester.pump(SensitiveClipboard.window + const Duration(seconds: 1));
    expect(clipboard, 'secret');
  });
}
