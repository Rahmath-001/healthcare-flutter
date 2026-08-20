@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/features/prescriptions/presentation/prescriptions_screen.dart';
import 'package:healthcare_mobile/features/records/presentation/records_screen.dart';

import '../support/pump.dart';

/// Golden files for the screens most likely to break silently.
///
/// The two overflow bugs a widget test caught — a records tile and an
/// appointment row, both spilling off the right of a normal phone — were
/// invisible to every other kind of test in this repo. Goldens catch the next
/// one, and catch it as a picture rather than as an assertion nobody wrote.
///
/// Regenerate deliberately, never reflexively:
///
///     flutter test --update-goldens --tags golden
///
/// Goldens are font-dependent, so these run only under the `golden` tag and are
/// excluded from the default suite — CI on a different platform would otherwise
/// fail on antialiasing rather than on anything real.
void main() {
  useFreshBackend();

  testWidgets('records list', (tester) async {
    await pumpScreen(tester, const RecordsScreen());
    await settleFixtures(tester);

    await expectLater(
      find.byType(RecordsScreen),
      matchesGoldenFile('goldens/records_list.png'),
    );
  });

  testWidgets('records list in Hindi', (tester) async {
    // The layout has to survive Devanagari, which sets taller line boxes than
    // Latin at the same point size — a row that just fits in English can clip.
    await pumpScreen(
      tester,
      const RecordsScreen(),
      locale: const Locale('hi'),
    );
    await settleFixtures(tester);

    await expectLater(
      find.byType(RecordsScreen),
      matchesGoldenFile('goldens/records_list_hi.png'),
    );
  });

  testWidgets('prescriptions list', (tester) async {
    await pumpScreen(tester, const PrescriptionsScreen());
    await settleFixtures(tester);

    await expectLater(
      find.byType(PrescriptionsScreen),
      matchesGoldenFile('goldens/prescriptions_list.png'),
    );
  });
}
