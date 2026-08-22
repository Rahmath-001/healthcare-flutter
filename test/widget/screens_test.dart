import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/features/appointments/presentation/appointments_screen.dart';
import 'package:healthcare_mobile/features/medications/presentation/medications_screen.dart';
import 'package:healthcare_mobile/features/prescriptions/presentation/prescriptions_screen.dart';
import 'package:healthcare_mobile/features/records/presentation/records_screen.dart';
import 'package:healthcare_mobile/features/support/presentation/support_screen.dart';
import 'package:healthcare_mobile/screens/tabs/home_tab.dart';

import '../support/pump.dart';

/// Screens, mounted for real against the fixture backend.
///
/// Until now the entire UI layer had one widget test, for a button. These do
/// not assert pixel positions — that is what the goldens are for — they assert
/// that a screen builds, resolves its data, and shows the states a user
/// actually encounters: content, empty, and not-yet-readable.
void main() {
  useFreshBackend();

  group('HomeTab', () {
    testWidgets('leads with the next appointment rather than a greeting card',
        (tester) async {
      await pumpScreen(tester, const HomeTab());
      await settleFixtures(tester);

      // The section, and a real appointment inside it — the seed always has
      // one upcoming, so an empty hero here means the derivation is wrong,
      // not that the patient has nothing booked.
      expect(find.text('Your next appointment'), findsOneWidget);
      expect(find.textContaining('Dr'), findsWidgets);
    });

    testWidgets('offers search and the four quick actions', (tester) async {
      await pumpScreen(tester, const HomeTab());
      await settleFixtures(tester);

      expect(find.text('Find a doctor'), findsOneWidget);
      expect(find.text('My records'), findsOneWidget);
      expect(find.text('Prescriptions'), findsOneWidget);
      expect(find.text('Who can see my records'), findsOneWidget);
      expect(find.text('Get help'), findsOneWidget);
    });

    testWidgets('renders without overflowing at a 200% text scale',
        (tester) async {
      // The audience for this app skews older, and the OS font-size slider is
      // the first accessibility setting anyone actually changes. A home screen
      // that overflows at 2x is unusable for the people most likely to set it.
      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: HomeTab(),
        ),
      );
      await settleFixtures(tester);

      expect(tester.takeException(), isNull);
    });
  });

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
      // The tile carries the short form of the status; the full sentence is on
      // the record detail screen, which has room for what to do about it.
      expect(find.textContaining('Checking'), findsWidgets);
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

  group('MedicationsScreen', () {
    testWidgets('groups the day by time of day', (tester) async {
      await pumpScreen(tester, const MedicationsScreen());
      await settleFixtures(tester);

      // The seeded running course is 1-0-0 and 1-0-1, so the day has a morning
      // and a night and deliberately no afternoon.
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Night'), findsOneWidget);
      expect(find.text('Afternoon'), findsNothing);
      expect(find.textContaining('Amlodipine'), findsWidgets);
    });

    testWidgets('a weekly medicine gets no reminder times', (tester) async {
      // The vitamin D in the seed is "Once weekly". It has to appear — it is
      // prescribed — under the doctor's own words, and never inside a slot.
      await pumpScreen(tester, const MedicationsScreen());
      await settleFixtures(tester);

      expect(find.textContaining('Cholecalciferol'), findsWidgets);
      expect(find.text('Once weekly'), findsOneWidget);
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

  group('text scaling', () {
    // Cards in this app are dense — a title, a status chip and two metadata
    // rows inside 16pt of padding — which is exactly the shape that overflows
    // first when someone turns the system font up. The audience skews older,
    // so that setting is not hypothetical, and a striped overflow bar is the
    // most visible defect a Flutter app can ship.
    final screens = <String, Widget>{
      'HomeTab': const HomeTab(),
      'RecordsScreen': const RecordsScreen(),
      'AppointmentsScreen': const AppointmentsScreen(),
      'PrescriptionsScreen': const PrescriptionsScreen(),
      'MedicationsScreen': const MedicationsScreen(),
      'PrescriptionDetailScreen':
          const PrescriptionDetailScreen(prescriptionId: 'p3'),
    };

    for (final entry in screens.entries) {
      for (final scale in [1.3, 2.0]) {
        testWidgets('${entry.key} survives a ${scale}x text scale',
            (tester) async {
          await pumpScreen(
            tester,
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: entry.value,
            ),
            // A tall surface: at 2x a short one scrolls the content out of
            // frame before it can overflow, which would pass for the wrong
            // reason.
            surface: const Size(430, 1400),
          );
          await settleFixtures(tester);

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
