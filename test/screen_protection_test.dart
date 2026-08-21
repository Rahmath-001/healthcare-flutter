import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/security/screen_protection.dart';

/// Screenshot protection lifecycle.
///
/// The bug these cover shipped and was invisible: `ProtectedScreen` enabled
/// `FLAG_SECURE` on mount and released it on dispose, but the Records and
/// Prescriptions tabs are `StatefulShellRoute.indexedStack` branches, which are
/// never disposed once visited. So protection latched on for the life of the
/// process — the app blanked in the recents switcher forever after, and the
/// release path never executed at all.
///
/// It failed *safe*, which is exactly why nobody would have found it: the
/// symptom is a cosmetic annoyance, and the mechanism underneath it was
/// completely broken.
void main() {
  setUp(ScreenProtection.resetForTest);

  /// Mirrors what go_router does to an inactive branch:
  /// `Offstage(offstage: true, child: TickerMode(enabled: false, ...))`.
  Widget branch({required bool active, required Widget child}) => Offstage(
        offstage: !active,
        child: TickerMode(enabled: active, child: child),
      );

  testWidgets('a visible protected screen holds protection', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProtectedScreen(child: Text('phi')),
      ),
    );

    expect(ScreenProtection.holders, 1);
  });

  testWidgets('switching away from a shell tab releases it', (tester) async {
    Widget app(bool recordsActive) => MaterialApp(
          home: Stack(
            children: [
              branch(
                active: recordsActive,
                child: const ProtectedScreen(child: Text('records')),
              ),
              branch(active: !recordsActive, child: const Text('home')),
            ],
          ),
        );

    await tester.pumpWidget(app(true));
    expect(ScreenProtection.holders, 1);

    // Tab away. The branch stays mounted — that is the whole problem — so this
    // has to fall to zero on visibility, not on disposal.
    await tester.pumpWidget(app(false));
    expect(ScreenProtection.holders, 0);

    // And back.
    await tester.pumpWidget(app(true));
    expect(ScreenProtection.holders, 1);
  });

  testWidgets('nested protected screens are reference-counted', (tester) async {
    // A record detail pushed over the records list: both are protected and both
    // are ticking. Popping the detail must not unprotect the list underneath.
    await tester.pumpWidget(
      const MaterialApp(
        home: ProtectedScreen(
          child: ProtectedScreen(child: Text('detail over list')),
        ),
      ),
    );
    expect(ScreenProtection.holders, 2);

    await tester.pumpWidget(
      const MaterialApp(home: ProtectedScreen(child: Text('list'))),
    );
    expect(ScreenProtection.holders, 1);
  });

  testWidgets('disposal releases a held claim', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ProtectedScreen(child: Text('phi'))),
    );
    expect(ScreenProtection.holders, 1);

    await tester.pumpWidget(const MaterialApp(home: Text('no phi')));
    expect(ScreenProtection.holders, 0);
  });

  testWidgets('an unbalanced release cannot drive the count negative',
      (tester) async {
    // A negative count would mean the next acquire does not reach the platform,
    // silently leaving a PHI screen unprotected.
    await ScreenProtection.release();
    expect(ScreenProtection.holders, 0);

    await tester.pumpWidget(
      const MaterialApp(home: ProtectedScreen(child: Text('phi'))),
    );
    expect(ScreenProtection.holders, 1);
  });
}
