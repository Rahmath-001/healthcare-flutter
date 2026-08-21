import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_backend.dart';
import 'package:healthcare_mobile/core/theme/app_theme.dart';
import 'package:healthcare_mobile/l10n/l10n.dart';

/// Mounts one screen with everything it needs and nothing it does not.
///
/// The localisation delegates are the point: `AppLocalizations.of` is
/// non-nullable, so a screen that reads a string throws without them — which
/// makes every widget test here also a check that the l10n wiring survives.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Locale locale = const Locale('en'),
  Size surface = const Size(430, 932),
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The real theme, not a bare M3 default. Screens read tones, radii and
        // component defaults off it, so a test running against `ThemeData()`
        // is exercising a widget tree the app never renders.
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: screen,
      ),
    ),
  );
}

/// Advances past the fixture latency so a screen's data has arrived.
///
/// Deliberately **not** `pumpAndSettle`. Loading states animate on a loop —
/// the skeleton's sweep, a progress indicator — so settling never returns.
/// Pumping a fixed number of frames is the only thing that terminates, and it
/// is enough: the futures resolve on the first, and the entrance animations
/// (180-360ms) are done well inside the 1.2s this covers.
Future<void> settleFixtures(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// A backend seeded fresh for one test.
///
/// The fixtures share a single store — that is what makes booking show up in
/// the appointments list — so a test that writes has to start from the seed or
/// it inherits whatever the last one did.
void useFreshBackend() {
  setUp(FixtureBackend.resetShared);
}
