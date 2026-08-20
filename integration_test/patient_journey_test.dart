import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_backend.dart';
import 'package:healthcare_mobile/features/appointments/presentation/appointments_screen.dart';
import 'package:healthcare_mobile/features/records/presentation/records_screen.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/pump.dart';

/// End-to-end journeys on a real device or emulator.
///
///     flutter test integration_test
///
/// Separate from `test/` because these drive the app the way a person does —
/// through the widget tree, against the shared fixture backend — and assert the
/// *consequences* rather than one screen's contents. A booking that returns an
/// Appointment nobody can find is the exact bug this catches, and it is the bug
/// the old per-repository fixtures actually had.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(FixtureBackend.resetShared);

  testWidgets('a booked appointment appears in the patient\'s list',
      (tester) async {
    final backend = FixtureBackend.shared;

    // Booked through the backend rather than by driving the booking screen:
    // the journey being asserted is "a booking reaches the list", and tapping
    // through a date strip to get there tests the date strip instead.
    final doctor = backend.doctors.first;
    final start = DateTime.now().add(const Duration(days: 1, hours: 3));

    final booked = backend.book(
      doctor: doctor,
      start: start,
      end: start.add(const Duration(minutes: 30)),
      mode: doctor.modes.first,
      patientName: 'Priya Sharma',
      reasonForVisit: 'Integration test',
    );

    await pumpScreen(tester, const AppointmentsScreen());
    await settleFixtures(tester);

    expect(find.textContaining(doctor.name), findsWidgets);
    expect(
      backend.appointments().map((a) => a.id),
      contains(booked.id),
    );
  });

  testWidgets('an uploaded record becomes readable once it is checked',
      (tester) async {
    final backend = FixtureBackend.shared;

    final record = backend.addRecord(
      title: 'Integration Test Report',
      type: backend.records().first.type,
      recordedAt: DateTime.now().subtract(const Duration(days: 1)),
      fileName: 'report.pdf',
      sizeBytes: 4096,
      contentType: 'application/pdf',
      // Real duration, so the screen genuinely renders the pending state first.
      scanDuration: const Duration(milliseconds: 400),
    );

    await pumpScreen(tester, const RecordsScreen());
    await settleFixtures(tester);

    expect(find.text('Integration Test Report'), findsOneWidget);

    // Let the scan finish, then rebuild.
    await tester.pump(const Duration(seconds: 1));
    await pumpScreen(tester, const RecordsScreen());
    await settleFixtures(tester);

    expect(
      backend.records().firstWhere((r) => r.id == record.id).isReadable,
      isTrue,
    );
  });

  testWidgets('the app renders in Hindi end to end', (tester) async {
    await pumpScreen(
      tester,
      const RecordsScreen(),
      locale: const Locale('hi'),
    );
    await settleFixtures(tester);

    expect(find.text('स्वास्थ्य रिकॉर्ड'), findsOneWidget);
  });
}
