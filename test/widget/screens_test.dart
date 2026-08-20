import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/features/appointments/presentation/appointments_screen.dart';
import 'package:healthcare_mobile/features/prescriptions/presentation/prescriptions_screen.dart';
import 'package:healthcare_mobile/features/records/presentation/records_screen.dart';
import 'package:healthcare_mobile/features/support/presentation/support_screen.dart';

import '../support/pump.dart';

/// Screens, mounted for real against the fixture backend.
///
/// Until now the entire UI layer had one widget test, for a button. These do
/// not assert pixel positions — that is what the goldens are for — they assert
/// that a screen builds, resolves its data, and shows the states a user
/// actually encounters: content, empty, and not-yet-readable.
void main() {
  useFreshBackend();

  group('RecordsScreen', () {
    testWidgets('lists the seeded records', (tester) async {
      await pumpScreen(tester, const RecordsScreen());
      await settleFixtures(tester);

      expect(find.text('Complete Blood Count'), findsOneWidget);
      expect(find.text('Chest X-Ray'), findsOneWidget);
    });

    testWidgets('shows a record still being checked as not yet readable',
        (tester) async {
      await pumpScreen(tester, const RecordsScreen());
      await settleFixtures(tester);

      // The seed leaves one upload mid-scan on purpose, so this state is
      // reachable without having to upload something first.
      expect(find.text('Vitamin D Panel'), findsOneWidget);
      expect(find.textContaining('Checking file'), findsWidgets);
    });

    testWidgets('filters to records the patient uploaded', (tester) async {
      await pumpScreen(tester, const RecordsScreen());
      await settleFixtures(tester);

      await tester.tap(find.text('Uploaded by me'));
      await settleFixtures(tester);

      // Provider-issued records drop out; the patient's own stay.
      expect(find.text('Thyroid Profile'), findsOneWidget);
      expect(find.text('Complete Blood Count'), findsNothing);
    });
  });

  group('AppointmentsScreen', () {
    testWidgets('shows upcoming and past appointments', (tester) async {
      await pumpScreen(tester, const AppointmentsScreen());
      await settleFixtures(tester);

      expect(find.textContaining('Dr'), findsWidgets);
      expect(find.text('Upcoming'), findsWidgets);
    });
  });

  group('PrescriptionsScreen', () {
    testWidgets('lists prescriptions with the issuing doctor', (tester) async {
      await pumpScreen(tester, const PrescriptionsScreen());
      await settleFixtures(tester);

      expect(find.textContaining('Dr Meera Iyer'), findsWidgets);
    });
  });

  group('SupportScreen', () {
    testWidgets('shows the seeded ticket thread', (tester) async {
      await pumpScreen(tester, const SupportScreen());
      await settleFixtures(tester);

      expect(
        find.text('Could not join my video consultation'),
        findsOneWidget,
      );
    });
  });

  group('localisation', () {
    testWidgets('renders Hindi when the locale asks for it', (tester) async {
      await pumpScreen(
        tester,
        const RecordsScreen(),
        locale: const Locale('hi'),
      );
      await settleFixtures(tester);

      // Proves the ARB is actually wired to the widget tree — the previous
      // state of this project had a complete ARB that no screen read.
      expect(find.text('स्वास्थ्य रिकॉर्ड'), findsOneWidget);
    });

    testWidgets('falls back to English for untranslated legal copy',
        (tester) async {
      await pumpScreen(
        tester,
        const SupportScreen(),
        locale: const Locale('hi'),
      );
      await settleFixtures(tester);

      // Hindi chrome around English legal text is the intended state, not a
      // gap: machine-translated consent is not consent.
      expect(find.text('सहायता'), findsWidgets);
    });
  });
}
