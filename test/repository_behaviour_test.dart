import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_backend.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/features/appointments/data/appointment_repository.dart';
import 'package:healthcare_mobile/features/appointments/domain/appointment.dart';
import 'package:healthcare_mobile/features/availability/data/availability_repository.dart';
import 'package:healthcare_mobile/features/availability/domain/availability.dart';
import 'package:healthcare_mobile/features/booking/data/booking_repository.dart';
import 'package:healthcare_mobile/features/consent/data/consent_repository.dart';
import 'package:healthcare_mobile/features/consent/domain/consent.dart';
import 'package:healthcare_mobile/features/prescriptions/data/prescription_repository.dart';
import 'package:healthcare_mobile/features/prescriptions/domain/prescription.dart';
import 'package:healthcare_mobile/features/providers_search/data/doctor_fixtures.dart';
import 'package:healthcare_mobile/features/providers_search/data/doctor_repository.dart';
import 'package:healthcare_mobile/features/providers_search/domain/doctor.dart';
import 'package:healthcare_mobile/features/ratings/data/ratings_repository.dart';

const _fast = Duration.zero;

void main() {
  // The fixtures now share one in-memory backend, which is the point — booking
  // an appointment has to show up in the appointments list. That also means one
  // test's writes are visible to the next, so each starts from the seed.
  setUp(FixtureBackend.resetShared);

  group('doctor search', () {
    final repo = FixtureDoctorRepository(latency: _fast);

    test('empty filters return every doctor', () async {
      final results = await repo.search(const DoctorSearchFilters());
      expect(results.length, DoctorFixtures.all.length);
    });

    test('searches across name, specialty, hospital and city', () async {
      // FR-SRCH-001 lists all four as searchable.
      for (final q in ['Ananya', 'Cardiology', 'Apollo', 'Hyderabad']) {
        final results = await repo.search(DoctorSearchFilters(query: q));
        expect(results, isNotEmpty, reason: 'query: $q');
      }
    });

    test('filters compose rather than replace each other', () async {
      final results = await repo.search(const DoctorSearchFilters(
        city: 'Bengaluru',
        maxFeeInr: 700,
      ));
      for (final d in results) {
        expect(d.hospital.city, 'Bengaluru');
        expect(d.consultationFeeInr, lessThanOrEqualTo(700));
      }
    });

    test('mode filter excludes doctors who do not offer it', () async {
      final results = await repo.search(
        const DoctorSearchFilters(mode: ConsultationMode.inPerson),
      );
      for (final d in results) {
        expect(d.modes, contains(ConsultationMode.inPerson));
      }
    });

    test('results are ordered by rating', () async {
      final results = await repo.search(const DoctorSearchFilters());
      for (var i = 1; i < results.length; i++) {
        expect(results[i - 1].rating, greaterThanOrEqualTo(results[i].rating));
      }
    });

    test('an unknown id fails as not found, not as a crash', () async {
      await expectLater(
        repo.byId('nope'),
        throwsA(
            isA<Failure>().having((f) => f.kind, 'kind', FailureKind.notFound)),
      );
    });
  });

  group('booking', () {
    test('payments are deferred, so a booking confirms immediately', () async {
      final repo = FixtureBookingRepository(latency: _fast);
      final doctor = DoctorFixtures.all.first;
      final slot = AppointmentSlotFixture.make();

      final appointment = await repo.book(
        doctor: doctor,
        slot: slot,
        mode: ConsultationMode.video,
        patientName: 'You',
      );

      expect(BookingPolicy.requiresPayment(), isFalse);
      expect(appointment.status.isUpcoming, isTrue);
      expect(appointment.paymentStatus.name, 'notRequired');
      expect(appointment.referenceCode, startsWith('MD-'));
    });

    test('booking the same slot twice conflicts', () async {
      // The server enforces this with an exclusion constraint; the client must
      // surface it as a conflict rather than a generic error.
      final repo = FixtureBookingRepository(latency: _fast);
      final doctor = DoctorFixtures.all.first;
      final slot = AppointmentSlotFixture.make();

      await repo.book(
        doctor: doctor,
        slot: slot,
        mode: ConsultationMode.video,
        patientName: 'You',
      );

      await expectLater(
        repo.book(
          doctor: doctor,
          slot: slot,
          mode: ConsultationMode.video,
          patientName: 'Someone else',
        ),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'SLOT_TAKEN')
            .having((f) => f.kind, 'kind', FailureKind.conflict)),
      );
    });

    test('reference codes avoid easily confused characters', () async {
      final repo = FixtureBookingRepository(latency: _fast);
      for (var i = 0; i < 20; i++) {
        final a = await repo.book(
          doctor: DoctorFixtures.all.first,
          slot: AppointmentSlotFixture.make(id: 'slot-$i', slotIndex: i),
          mode: ConsultationMode.video,
          patientName: 'You',
        );
        // No 0/O/1/I: the code gets read out over the phone to support.
        expect(a.referenceCode.substring(3), isNot(matches(RegExp(r'[01OI]'))));
      }
    });
  });

  group('consent lifecycle', () {
    test('grant, then revoke, ends access immediately', () async {
      // The acceptance test for the whole consent design.
      final repo = FixtureConsentRepository(latency: _fast);

      final grant = await repo.grant(
        providerId: 'd1',
        providerName: 'Dr Ananya Sharma',
        providerSpecialty: 'Cardiology',
        scopeKind: ConsentScopeKind.allRecords,
        purpose: ConsentPurpose.consultation,
        duration: const Duration(days: 7),
      );
      expect(grant.isActive, isTrue);

      await repo.revoke(grant.id);

      final after = (await repo.grants()).firstWhere((g) => g.id == grant.id);
      expect(after.isRevoked, isTrue);
      expect(after.isActive, isFalse);
    });

    test('a grant longer than 180 days is refused', () async {
      final repo = FixtureConsentRepository(latency: _fast);
      await expectLater(
        repo.grant(
          providerId: 'd1',
          providerName: 'Dr X',
          providerSpecialty: 'GP',
          scopeKind: ConsentScopeKind.allRecords,
          purpose: ConsentPurpose.consultation,
          duration: const Duration(days: 365),
        ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'GRANT_TOO_LONG')),
      );
    });

    test('approving a request produces a time-boxed grant', () async {
      final repo = FixtureConsentRepository(latency: _fast);
      final pending = await repo.pendingRequests();
      expect(pending, isNotEmpty);

      final grant = await repo.approveRequest(
        pending.first.id,
        duration: const Duration(days: 7),
        scopeKind: ConsentScopeKind.allRecords,
      );

      expect(grant.isActive, isTrue);
      expect(grant.expiresAt.isAfter(DateTime.now()), isTrue);
      expect(await repo.pendingRequests(), isEmpty);
    });

    test('denying a request creates no grant', () async {
      final repo = FixtureConsentRepository(latency: _fast);
      final before = (await repo.grants()).length;
      final pending = await repo.pendingRequests();

      await repo.denyRequest(pending.first.id);

      expect((await repo.grants()).length, before);
      expect(await repo.pendingRequests(), isEmpty);
    });

    test('the access log records denials as well as reads', () async {
      final repo = FixtureConsentRepository(latency: _fast);
      final log = await repo.accessLog();
      expect(log.any((e) => e.action == AccessAction.denied), isTrue);
    });
  });

  group('prescribing', () {
    test('a prohibited drug is refused at issue time', () async {
      final repo = FixturePrescriptionRepository(latency: _fast);
      await expectLater(
        repo.issue(
          appointmentId: 'a1',
          patientName: 'You',
          patientAge: '30',
          patientGender: 'Female',
          isFollowUp: true,
          items: const [
            PrescriptionItem(
              drugName: 'Alprazolam',
              genericName: 'Alprazolam',
              strength: '0.5 mg',
              form: 'Tablet',
              frequency: '0-0-1',
              durationDays: 5,
            ),
          ],
        ),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'DRUG_NOT_PERMITTED')),
      );
    });

    test('a List B drug is refused on a first consultation', () async {
      final repo = FixturePrescriptionRepository(latency: _fast);
      await expectLater(
        repo.issue(
          appointmentId: 'a1',
          patientName: 'You',
          patientAge: '30',
          patientGender: 'Female',
          isFollowUp: false,
          items: const [
            PrescriptionItem(
              drugName: 'Metformin',
              genericName: 'Metformin hydrochloride',
              strength: '500 mg',
              form: 'Tablet',
              frequency: '1-0-1',
              durationDays: 30,
            ),
          ],
        ),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'DRUG_NOT_PERMITTED')),
      );
    });

    test('an issued prescription snapshots the registration number', () async {
      final repo = FixturePrescriptionRepository(latency: _fast);
      final p = await repo.issue(
        appointmentId: 'a1',
        patientName: 'You',
        patientAge: '30',
        patientGender: 'Female',
        isFollowUp: false,
        items: const [
          PrescriptionItem(
            drugName: 'Paracetamol',
            genericName: 'Paracetamol',
            strength: '500 mg',
            form: 'Tablet',
            frequency: '1-1-1',
            durationDays: 3,
          ),
        ],
      );

      expect(p.providerRegistrationNumber, isNotEmpty);
      expect(p.verificationCode, isNotEmpty);
      expect(p.retainedUntil.year, p.issuedAt.year + 3);
    });

    test('an empty prescription is refused', () async {
      final repo = FixturePrescriptionRepository(latency: _fast);
      await expectLater(
        repo.issue(
          appointmentId: 'a1',
          patientName: 'You',
          patientAge: '30',
          patientGender: 'Female',
          isFollowUp: false,
          items: const [],
        ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'NO_ITEMS')),
      );
    });
  });

  group('availability', () {
    test('overlapping hours on the same day are refused', () async {
      final repo = FixtureAvailabilityRepository(latency: _fast);
      // Monday 09:00-13:00 already exists in the fixture.
      await expectLater(
        repo.addRule(
          weekday: DateTime.monday,
          start: const TimeOfDayValue(12, 0),
          end: const TimeOfDayValue(15, 0),
          mode: ConsultationMode.video,
          slotMinutes: 30,
        ),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'OVERLAPPING_AVAILABILITY')),
      );
    });

    test('an end before the start is refused', () async {
      final repo = FixtureAvailabilityRepository(latency: _fast);
      await expectLater(
        repo.addRule(
          weekday: DateTime.sunday,
          start: const TimeOfDayValue(15, 0),
          end: const TimeOfDayValue(9, 0),
          mode: ConsultationMode.video,
          slotMinutes: 30,
        ),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'INVALID_TIME_RANGE')),
      );
    });

    test('non-overlapping hours on the same day are accepted', () async {
      final repo = FixtureAvailabilityRepository(latency: _fast);
      final rule = await repo.addRule(
        weekday: DateTime.monday,
        start: const TimeOfDayValue(20, 30),
        end: const TimeOfDayValue(22, 0),
        mode: ConsultationMode.video,
        slotMinutes: 15,
      );
      expect(rule.slotCount, 6);
    });
  });

  group('ratings', () {
    test('one rating per appointment', () async {
      final repo = FixtureRatingsRepository(latency: _fast);
      await repo.submit(
        appointmentId: 'a9',
        doctorName: 'Dr X',
        stars: 5,
      );
      await expectLater(
        repo.submit(appointmentId: 'a9', doctorName: 'Dr X', stars: 4),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'ALREADY_RATED')),
      );
    });

    test('a new rating is held for moderation, not published', () async {
      final repo = FixtureRatingsRepository(latency: _fast);
      final rating = await repo.submit(
        appointmentId: 'a10',
        doctorName: 'Dr X',
        stars: 5,
      );
      expect(rating.status.name, 'pendingModeration');
    });

    test('star ratings outside 1-5 are refused', () async {
      final repo = FixtureRatingsRepository(latency: _fast);
      for (final stars in [0, 6, -1]) {
        await expectLater(
          repo.submit(appointmentId: 'x$stars', doctorName: 'Dr', stars: stars),
          throwsA(
              isA<Failure>().having((f) => f.code, 'code', 'INVALID_RATING')),
        );
      }
    });
  });

  group('appointments', () {
    test('cancelling a past appointment is refused', () async {
      final repo = FixtureAppointmentRepository(latency: _fast);
      final all = await repo.listForPatient();
      final past = all.firstWhere((a) => a.status.isPast);

      await expectLater(
        repo.cancel(past.id, reason: 'changed my mind'),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'CANCELLATION_WINDOW_CLOSED')),
      );
    });

    test('cancelling an upcoming appointment records the reason', () async {
      final repo = FixtureAppointmentRepository(latency: _fast);
      final all = await repo.listForPatient();
      final upcoming = all.firstWhere((a) => a.canCancel);

      final result =
          await repo.cancel(upcoming.id, reason: 'No longer available');

      expect(result.status.isCancelled, isTrue);
      expect(result.cancellationReason, 'No longer available');
    });
  });
}

/// Small helper so booking tests do not each rebuild a slot by hand.
abstract final class AppointmentSlotFixture {
  /// A bookable slot tomorrow, [slotIndex] half-hours after 9am.
  ///
  /// The index moves the *time*, not just the id, because a slot lock is keyed
  /// by doctor and start instant — the same deterministic id the server uses.
  /// Two slots that differ only by label are the same slot, and the fixture is
  /// right to refuse the second one.
  static AppointmentSlot make({String id = 'slot-1', int slotIndex = 0}) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9)
        .add(Duration(minutes: 30 * slotIndex));
    return AppointmentSlot(
      id: id,
      start: start,
      end: start.add(const Duration(minutes: 30)),
      mode: ConsultationMode.video,
    );
  }
}
