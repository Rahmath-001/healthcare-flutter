import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/providers.dart';
import 'package:healthcare_mobile/core/security/inactivity_timeout.dart';
import 'package:healthcare_mobile/core/session/session.dart';
import 'package:healthcare_mobile/core/session/session_controller.dart';
import 'package:healthcare_mobile/core/session/user_role.dart';
import 'package:healthcare_mobile/l10n/l10n.dart';

/// Automatic logoff.
///
/// A security control nobody tests is a security control that quietly stops
/// working — and this one fails *open*: if the timer breaks, nothing throws,
/// nothing looks wrong, and every session simply stays alive forever on an
/// unattended phone. The only way to know it still works is to assert it.
void main() {
  Session session() => Session(
        userId: 'u',
        sessionId: 's',
        accessToken: 't',
        accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
        role: UserRole.patient,
        accountStatus: AccountStatus.active,
        providerStatus: ProviderStatus.notApplicable,
        scopes: const {},
        permissionVersion: 1,
      );

  /// A clock the test moves by hand, so the background branch is reachable.
  var clock = DateTime(2026, 8, 21, 9);
  setUp(() => clock = DateTime(2026, 8, 21, 9));

  Future<_FakeSessionController> pump(
    WidgetTester tester, {
    required Session? initial,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final controller = _FakeSessionController(initial);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InactivityTimeout(
              duration: timeout,
              now: () => clock,
              child: const SizedBox.expand(child: Text('app')),
            ),
          ),
        ),
      ),
    );
    // Lets the AsyncNotifier's build() future settle into a data state.
    await tester.pump();
    return controller;
  }

  testWidgets('signs out once the window elapses with no interaction',
      (tester) async {
    final controller = await pump(tester, initial: session());

    await tester.pump(const Duration(seconds: 9));
    expect(controller.signOutCalls, 0, reason: 'still inside the window');

    await tester.pump(const Duration(seconds: 2));
    expect(controller.signOutCalls, 1);
  });

  testWidgets('a tap re-arms the clock', (tester) async {
    final controller = await pump(tester, initial: session());

    await tester.pump(const Duration(seconds: 8));
    await tester.tap(find.text('app'));
    await tester.pump(const Duration(seconds: 8));

    // 16s of wall time but only 8s since the tap.
    expect(controller.signOutCalls, 0);

    await tester.pump(const Duration(seconds: 3));
    expect(controller.signOutCalls, 1);
  });

  testWidgets('does nothing when nobody is signed in', (tester) async {
    // Otherwise the sign-in screen "times out" every 15 minutes and wipes a
    // half-entered phone number for a session that does not exist.
    final controller = await pump(tester, initial: null);

    await tester.pump(const Duration(seconds: 11));
    expect(controller.signOutCalls, 0);
  });

  testWidgets('expires on resume when the app was backgrounded for longer',
      (tester) async {
    // The real gap this covers: timers do not fire reliably in the background
    // and an iOS process can be suspended outright, so elapsed time has to be
    // measured against the wall clock on the way back in. Without this a user
    // could background the app for a day and return to a live session.
    final controller = await pump(tester, initial: session());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = clock.add(const Duration(hours: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(controller.signOutCalls, 1);
  });

  testWidgets('a short trip out of the app does not sign you out',
      (tester) async {
    // Answering a message and coming straight back is not an absence.
    final controller = await pump(tester, initial: session());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = clock.add(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(controller.signOutCalls, 0);

    // And the clock is running again from the resume, not from before it.
    await tester.pump(const Duration(seconds: 11));
    expect(controller.signOutCalls, 1);
  });
}

/// A [SessionController] that touches neither secure storage nor the network.
///
/// `build()` is overridden, which is what keeps the real `_restore()` — and the
/// `flutter_secure_storage` platform channel behind it — out of the test.
class _FakeSessionController extends SessionController {
  _FakeSessionController(this._initial);

  final Session? _initial;
  int signOutCalls = 0;

  @override
  Future<Session?> build() async => _initial;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    state = const AsyncValue<Session?>.data(null);
  }
}
