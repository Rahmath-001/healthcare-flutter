import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_backend.dart';
import 'package:healthcare_mobile/core/fixtures/provider_application.dart';
import 'package:healthcare_mobile/features/appointments/data/appointment_repository.dart';
import 'package:healthcare_mobile/features/availability/data/availability_repository.dart';
import 'package:healthcare_mobile/features/booking/data/booking_repository.dart';
import 'package:healthcare_mobile/features/consent/data/consent_repository.dart';
import 'package:healthcare_mobile/features/consent/domain/consent.dart';
import 'package:healthcare_mobile/features/credentials/data/credentials_repository.dart';
import 'package:healthcare_mobile/features/credentials/domain/credential.dart';
import 'package:healthcare_mobile/features/prescriptions/data/prescription_repository.dart';
import 'package:healthcare_mobile/features/prescriptions/domain/prescription.dart';
import 'package:healthcare_mobile/features/providers_search/data/doctor_fixtures.dart';
import 'package:healthcare_mobile/features/providers_search/domain/doctor.dart';
import 'package:healthcare_mobile/features/ratings/data/ratings_repository.dart';
import 'package:healthcare_mobile/features/ratings/domain/rating.dart';
import 'package:healthcare_mobile/features/records/data/records_repository.dart';
import 'package:healthcare_mobile/features/records/domain/medical_record.dart';

import 'support/test_files.dart';

/// The fixtures as a *product*, not as isolated repositories.
///
/// Every test here is a consequence that crosses a feature boundary, because
/// that is exactly what the old per-repository fixtures could not do: booking
/// returned an appointment the appointments list had never heard of, an upload
/// stayed "checking…" forever, and a prescription never reached the patient.
/// Each screen demoed correctly and the product did not work.
void main() {
  const fast = Duration.zero;

  setUp(FixtureBackend.resetShared);

  group('booking reaches the appointments list', () {
    test('a booked slot becomes one of the patient\'s appointments', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);

      final before = await appointments.listForPatient();
      final slots = await booking.slotsFor(
        doctorId: 'd1',
        date: DateTime.now().add(const Duration(days: 1)),
        mode: ConsultationMode.video,
      );
      final free = slots.firstWhere((s) => s.isAvailable);

      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d1'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
        reasonForVisit: 'Chest tightness',
      );

      final after = await appointments.listForPatient();
      expect(after.length, before.length + 1);
      expect(after.map((a) => a.id), contains(booked.id));
      expect(
        after.firstWhere((a) => a.id == booked.id).reasonForVisit,
        'Chest tightness',
      );
    });

    test('a booked slot stops being offered', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final date = DateTime.now().add(const Duration(days: 1));

      final free = (await booking.slotsFor(
        doctorId: 'd1',
        date: date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable);

      await booking.book(
        doctor: DoctorFixtures.byId('d1'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      final again = await booking.slotsFor(
        doctorId: 'd1',
        date: date,
        mode: ConsultationMode.video,
      );
      expect(again.firstWhere((s) => s.id == free.id).isAvailable, isFalse);
    });

    test('cancelling returns the slot to the pool', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);
      final date = DateTime.now().add(const Duration(days: 1));

      final free = (await booking.slotsFor(
        doctorId: 'd2',
        date: date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable);

      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d2'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );
      await appointments.cancel(booked.id, reason: 'Plans changed');

      final again = await booking.slotsFor(
        doctorId: 'd2',
        date: date,
        mode: ConsultationMode.video,
      );
      // A cancellation that helps nobody else is not a cancellation.
      expect(again.firstWhere((s) => s.id == free.id).isAvailable, isTrue);
    });
  });

  group('records become readable', () {
    test('an upload starts unreadable and finishes readable', () async {
      // Zero scan time here; the app uses a real delay so the "checking" state
      // is visible, which is a state the UI has to handle.
      final records =
          FixtureRecordsRepository(latency: fast, scanDuration: fast);

      final uploaded = await records.upload(
        title: 'Lipid Profile',
        type: RecordType.labReport,
        recordedAt: DateTime.now().subtract(const Duration(days: 1)),
        file: testFile(name: 'lipids.pdf'),
      );

      expect(uploaded.scanStatus, ScanStatus.pending);

      final listed = await records.listOwn();
      final settled = listed.firstWhere((r) => r.id == uploaded.id);
      expect(settled.scanStatus, ScanStatus.clean);
      expect(settled.isReadable, isTrue);
    });

    test('a record that has not been checked cannot be downloaded', () async {
      final records = FixtureRecordsRepository(
        latency: fast,
        scanDuration: const Duration(seconds: 30),
      );

      final uploaded = await records.upload(
        title: 'Ultrasound',
        type: RecordType.scan,
        recordedAt: DateTime.now(),
        file: testFile(name: 'scan.jpg'),
      );

      await expectLater(
        records.downloadUrl(uploaded.id),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'RECORD_NOT_READY')),
      );
    });

    test('deleting a record removes it from the list', () async {
      final records =
          FixtureRecordsRepository(latency: fast, scanDuration: fast);
      final before = await records.listOwn();

      await records.delete(before.first.id);

      final after = await records.listOwn();
      expect(after.map((r) => r.id), isNot(contains(before.first.id)));
    });
  });

  group('consent gates what a provider can see', () {
    test('a provider with no grant is refused, and the denial is logged',
        () async {
      final records = FixtureRecordsRepository(latency: fast);
      final consent = FixtureConsentRepository(latency: fast);

      await expectLater(
        records.listGranted('d8'),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'NO_CONSENT')),
      );

      final log = await consent.accessLog();
      expect(log.first.action, AccessAction.denied);
    });

    test('granting access opens exactly the records the grant covers',
        () async {
      final records = FixtureRecordsRepository(latency: fast);
      final consent = FixtureConsentRepository(latency: fast);

      final all = await records.listOwn();
      final one = all.firstWhere((r) => r.isReadable);

      await consent.grant(
        providerId: 'd8',
        providerName: 'Dr Kavita Menon',
        providerSpecialty: 'ENT',
        scopeKind: ConsentScopeKind.specificRecords,
        purpose: ConsentPurpose.consultation,
        duration: const Duration(days: 30),
        recordIds: [one.id],
      );

      final visible = await records.listGranted('d8');
      expect(visible.map((r) => r.id), [one.id]);
    });

    test('revoking ends access immediately', () async {
      final records = FixtureRecordsRepository(latency: fast);
      final consent = FixtureConsentRepository(latency: fast);

      final grant = await consent.grant(
        providerId: 'd8',
        providerName: 'Dr Kavita Menon',
        providerSpecialty: 'ENT',
        scopeKind: ConsentScopeKind.allRecords,
        purpose: ConsentPurpose.consultation,
        duration: const Duration(days: 30),
      );
      expect(await records.listGranted('d8'), isNotEmpty);

      await consent.revoke(grant.id);

      await expectLater(
        records.listGranted('d8'),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'NO_CONSENT')),
      );
    });
  });

  group('prescribing reaches the patient', () {
    test(
        'an issued prescription appears in the patient\'s list and marks '
        'the appointment', () async {
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);

      // a4 is completed and has no prescription in the seed.
      final target =
          (await appointments.listForPatient()).firstWhere((a) => a.id == 'a4');
      final before = await prescriptions.listForPatient();

      final issued = await prescriptions.issue(
        appointmentId: target.id,
        patientName: target.patientName,
        patientAge: '32',
        patientGender: 'Female',
        isFollowUp: true,
        items: const [
          PrescriptionItem(
            drugName: 'Paracetamol',
            genericName: 'Paracetamol',
            strength: '650 mg',
            form: 'Tablet',
            frequency: '1-0-1',
            durationDays: 3,
          ),
        ],
      );

      final after = await prescriptions.listForPatient();
      expect(after.length, before.length + 1);
      expect(after.map((p) => p.id), contains(issued.id));

      final updated = await appointments.byId(target.id);
      expect(updated.hasPrescription, isTrue);
    });
  });

  group('rating a consultation', () {
    test('submitting marks the appointment and queues for moderation',
        () async {
      final ratings = FixtureRatingsRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);

      final rating = await ratings.submit(
        appointmentId: 'a4',
        doctorName: 'Dr Rajesh Kumar',
        stars: 5,
        comment: 'Very thorough.',
      );

      expect(rating.status, RatingStatus.pendingModeration);
      expect((await appointments.byId('a4')).hasRating, isTrue);
    });

    test('the same appointment cannot be rated twice', () async {
      final ratings = FixtureRatingsRepository(latency: fast);
      await ratings.submit(
        appointmentId: 'a4',
        doctorName: 'Dr Rajesh Kumar',
        stars: 4,
      );

      await expectLater(
        ratings.submit(
          appointmentId: 'a4',
          doctorName: 'Dr Rajesh Kumar',
          stars: 1,
        ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'ALREADY_RATED')),
      );
    });
  });

  group('availability changes what patients can book', () {
    test('blocking a day empties its slot grid', () async {
      final availability = FixtureAvailabilityRepository(latency: fast);
      final booking = FixtureBookingRepository(latency: fast);
      // Sundays are closed in the fixture, so an unlucky "two days from now"
      // would find an empty grid before anything was blocked and pass for the
      // wrong reason.
      var day = DateTime.now().add(const Duration(days: 2));
      while (day.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
      }

      expect(
        await booking.slotsFor(
          doctorId: 'd1',
          date: day,
          mode: ConsultationMode.video,
        ),
        isNotEmpty,
      );

      await availability.blockDay(day, reason: 'Conference');

      // A block that a patient cannot feel is not a block.
      expect(
        await booking.slotsFor(
          doctorId: 'd1',
          date: day,
          mode: ConsultationMode.video,
        ),
        isEmpty,
      );
    });
  });

  group('the two apps meet', () {
    test('submitting credentials puts an application in the review queue',
        () async {
      final credentials = FixtureCredentialsRepository(latency: fast);
      final backend = FixtureBackend.shared;
      final before = backend.applications().length;

      // Work through the gate the way a doctor would.
      await credentials.uploadDocument(
        kind: CredentialKind.hospitalAffiliation,
        fileName: 'affiliation.pdf',
        sizeBytes: 120 * 1024,
        file: testFile(name: 'affiliation.pdf'),
      );
      await credentials.verifyIdentityWithDigiLocker();
      await credentials.setRegistrationNumber('KMC-99881');
      await credentials.confirmMfaEnrolment('123456');

      final ready = await credentials.checklist();
      expect(ready.canSubmit, isTrue);

      await credentials.submitForReview();

      final applications = backend.applications();
      expect(applications.length, before + 1);
      expect(
        applications.first.status,
        ProviderApplicationStatus.submitted,
      );
      expect(applications.first.registrationNumber, 'KMC-99881');
    });

    test('an incomplete checklist cannot be submitted', () async {
      final credentials = FixtureCredentialsRepository(latency: fast);

      // The seed leaves identity, affiliation, registration and MFA undone.
      await expectLater(
        credentials.submitForReview(),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'CHECKLIST_INCOMPLETE')),
      );
    });
  });

  group('isolation', () {
    test('resetting restores the seeded state', () async {
      final records =
          FixtureRecordsRepository(latency: fast, scanDuration: fast);
      final seeded = (await records.listOwn()).length;

      await records.upload(
        title: 'Extra',
        type: RecordType.other,
        recordedAt: DateTime.now(),
        file: testFile(name: 'extra.pdf'),
      );
      expect((await records.listOwn()).length, seeded + 1);

      FixtureBackend.resetShared();

      // A new repository picks up the fresh shared instance.
      final fresh = FixtureRecordsRepository(latency: fast);
      expect((await fresh.listOwn()).length, seeded);
    });
  });
}
