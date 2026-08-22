import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_backend.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_seed.dart';
import 'package:healthcare_mobile/core/fixtures/provider_application.dart';
import 'package:healthcare_mobile/features/appointments/data/appointment_repository.dart';
import 'package:healthcare_mobile/features/appointments/domain/appointment.dart';
import 'package:healthcare_mobile/features/availability/data/availability_repository.dart';
import 'package:healthcare_mobile/features/booking/data/booking_repository.dart';
import 'package:healthcare_mobile/features/booking/domain/waitlist.dart';
import 'package:healthcare_mobile/features/consent/data/consent_repository.dart';
import 'package:healthcare_mobile/features/consent/domain/consent.dart';
import 'package:healthcare_mobile/features/consultation/data/consultation_note_repository.dart';
import 'package:healthcare_mobile/features/notifications/data/notification_repository.dart';
import 'package:healthcare_mobile/features/notifications/domain/notification.dart';
import 'package:healthcare_mobile/features/credentials/data/credentials_repository.dart';
import 'package:healthcare_mobile/features/credentials/domain/credential.dart';
import 'package:healthcare_mobile/features/prescriptions/data/prescription_repository.dart';
import 'package:healthcare_mobile/features/prescriptions/domain/prescription.dart';
import 'package:healthcare_mobile/features/prescriptions/domain/refill_request.dart';
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

  /// A future date the fixture actually opens on.
  ///
  /// `slotsFor` returns nothing on a Sunday — a deliberate closed day, so the
  /// UI has a real empty state to render. Tests that reached for
  /// "tomorrow" therefore passed six days a week and failed on Saturdays,
  /// which is the worst kind of red build: nothing changed, and it is green
  /// again by Monday. Skipping the closed day makes the date irrelevant.
  DateTime openDay({int from = 1}) {
    var date = DateTime.now().add(Duration(days: from));
    while (date.weekday == DateTime.sunday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  group('booking reaches the appointments list', () {
    test('a booked slot becomes one of the patient\'s appointments', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);

      final before = await appointments.listForPatient();
      final slots = await booking.slotsFor(
        doctorId: 'd1',
        date: openDay(),
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
      final date = openDay();

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
      final date = openDay();

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

  group('the doctor writes up the consultation', () {
    Future<Appointment> completed(
      FixtureAppointmentRepository appointments,
    ) async =>
        (await appointments.listForPatient())
            .firstWhere((a) => a.status.isPast);

    test('a note reaches the patient, and says who signed it', () async {
      // The consent every patient agrees to says the doctor's notes are kept
      // as part of their record. Until this existed, that statement was false
      // — and its exact wording is hashed into the consent record.
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notes = FixtureConsultationNoteRepository(latency: fast);
      final appointment = await completed(appointments);

      expect(await notes.forAppointment(appointment.id), isNull);

      final note = await notes.write(
        appointment.id,
        body: 'Reviewed symptoms. Advised rest and fluids.',
      );

      expect(note.body, 'Reviewed symptoms. Advised rest and fluids.');
      expect(note.authorName, isNotEmpty);
      // On the note for the same reason it is on a prescription: it is what
      // makes this a clinical record rather than a message from somebody.
      expect(note.authorRegistrationNumber, isNotEmpty);
      expect(note.hasAddenda, isFalse);

      final readBack = await notes.forAppointment(appointment.id);
      expect(readBack!.id, note.id);
    });

    test('a note cannot be written twice, only appended to', () async {
      // Editing a clinical note silently rewrites the past, and the occasions
      // one most needs changing are exactly the ones where somebody has an
      // interest in the earlier version disappearing.
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notes = FixtureConsultationNoteRepository(latency: fast);
      final appointment = await completed(appointments);

      await notes.write(appointment.id, body: 'Initial impression.');

      await expectLater(
        notes.write(appointment.id, body: 'Actually, something else.'),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'NOTE_EXISTS')),
      );
    });

    test('an addendum is added without touching the original', () async {
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notes = FixtureConsultationNoteRepository(latency: fast);
      final appointment = await completed(appointments);

      final note = await notes.write(appointment.id, body: 'Initial view.');
      final amended = await notes.addAddendum(
        note.id,
        body: 'Lab result since received; treatment unchanged.',
      );

      expect(amended.body, 'Initial view.', reason: 'the original is fixed');
      expect(amended.addenda.length, 1);
      expect(amended.addenda.single.body, contains('Lab result'));
      expect(amended.addenda.single.writtenAt, isNotNull);
      // The "last updated" label follows the addendum, not the original.
      expect(amended.lastUpdatedAt, amended.addenda.single.writtenAt);
    });

    test('addenda accumulate in order', () async {
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notes = FixtureConsultationNoteRepository(latency: fast);
      final appointment = await completed(appointments);

      final note = await notes.write(appointment.id, body: 'First.');
      await notes.addAddendum(note.id, body: 'Second.');
      final third = await notes.addAddendum(note.id, body: 'Third.');

      expect(third.addenda.map((a) => a.body), ['Second.', 'Third.']);
    });

    test('a consultation that has not begun cannot be written up', () async {
      // A note against a booking nobody has attended is a record of an event
      // that has not happened.
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notes = FixtureConsultationNoteRepository(latency: fast);
      final upcoming = (await appointments.listForPatient())
          .firstWhere((a) => a.status == AppointmentStatus.confirmed);

      await expectLater(
        notes.write(upcoming.id, body: 'Seen and treated.'),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'CONSULTATION_NOT_STARTED')),
      );
    });

    test('an empty note is refused', () async {
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notes = FixtureConsultationNoteRepository(latency: fast);
      final appointment = await completed(appointments);

      await expectLater(
        notes.write(appointment.id, body: '   '),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'NOTE_EMPTY')),
      );
    });

    test('the patient is told, without any clinical detail', () async {
      // The notification lands on a lock screen. It says a note exists; the
      // note itself stays behind authentication.
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notes = FixtureConsultationNoteRepository(latency: fast);
      final notifications = FixtureNotificationRepository(latency: fast);
      final appointment = await completed(appointments);

      await notes.write(
        appointment.id,
        body: 'Suspected hypertension. Start amlodipine.',
      );

      final told = (await notifications.list())
          .firstWhere((n) => n.kind == NotificationKind.recordReady);
      expect(told.body, isNot(contains('amlodipine')));
      expect(told.body, isNot(contains('hypertension')));
      expect(told.targetId, appointment.id);
    });
  });

  group('a cancellation reaches the waiting list', () {
    test('joining, then a cancellation, tells the waiting patient', () async {
      // The consequence the feature exists for: a cancelled slot is only
      // useful if somebody other than the canceller hears about it.
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notifications = FixtureNotificationRepository(latency: fast);
      final date = openDay();

      final free = (await booking.slotsFor(
        doctorId: 'd1',
        date: date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable);

      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d1'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      final entry = await booking.joinWaitlist(
        doctor: DoctorFixtures.byId('d1'),
        mode: ConsultationMode.video,
        preferredDate: date,
      );
      expect(entry.isActive, isTrue);

      final before = (await notifications.list()).length;
      await appointments.cancel(booked.id, reason: 'Plans changed');

      expect((await notifications.list()).length, greaterThan(before));

      // The entry is spent. One that stayed active would ping this person on
      // every cancellation for the rest of the month.
      final after =
          (await booking.waitlist()).firstWhere((e) => e.id == entry.id);
      expect(after.status, WaitlistStatus.notified);
      expect(after.isActive, isFalse);
      expect(after.notifiedAt, isNotNull);
    });

    test('rescheduling away frees the old slot for the list too', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);
      final date = openDay();

      final free = (await booking.slotsFor(
        doctorId: 'd2',
        date: date,
        mode: ConsultationMode.video,
      ))
          .where((s) => s.isAvailable)
          .toList();

      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d2'),
        slot: free.first,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      final entry = await booking.joinWaitlist(
        doctor: DoctorFixtures.byId('d2'),
        mode: ConsultationMode.video,
        preferredDate: date,
      );

      await appointments.reschedule(
        booked.id,
        start: free[1].start,
        end: free[1].end,
      );

      final after =
          (await booking.waitlist()).firstWhere((e) => e.id == entry.id);
      expect(after.status, WaitlistStatus.notified);
    });

    test('a different doctor or mode is a different list', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);
      final date = openDay();

      final free = (await booking.slotsFor(
        doctorId: 'd1',
        date: date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable);
      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d1'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      // Waiting on a different doctor entirely.
      final other = await booking.joinWaitlist(
        doctor: DoctorFixtures.byId('d3'),
        mode: ConsultationMode.video,
      );
      // ...and on the right doctor but the wrong consultation type.
      final wrongMode = await booking.joinWaitlist(
        doctor: DoctorFixtures.byId('d1'),
        mode: ConsultationMode.inPerson,
      );

      await appointments.cancel(booked.id, reason: 'Plans changed');

      final list = await booking.waitlist();
      expect(list.firstWhere((e) => e.id == other.id).isActive, isTrue);
      expect(list.firstWhere((e) => e.id == wrongMode.id).isActive, isTrue);
    });

    test('an entry for another day is not woken', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);
      final date = openDay();

      final free = (await booking.slotsFor(
        doctorId: 'd1',
        date: date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable);
      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d1'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      final otherDay = await booking.joinWaitlist(
        doctor: DoctorFixtures.byId('d1'),
        mode: ConsultationMode.video,
        preferredDate: openDay(from: 9),
      );

      await appointments.cancel(booked.id, reason: 'Plans changed');

      expect(
        (await booking.waitlist())
            .firstWhere((e) => e.id == otherDay.id)
            .isActive,
        isTrue,
      );
    });

    test('an "any day" entry takes the first thing going', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);
      final date = openDay();

      final free = (await booking.slotsFor(
        doctorId: 'd1',
        date: date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable);
      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d1'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      final anyDay = await booking.joinWaitlist(
        doctor: DoctorFixtures.byId('d1'),
        mode: ConsultationMode.video,
      );

      await appointments.cancel(booked.id, reason: 'Plans changed');

      expect(
        (await booking.waitlist()).firstWhere((e) => e.id == anyDay.id).status,
        WaitlistStatus.notified,
      );
    });

    test('joining the same list twice is refused', () async {
      final booking = FixtureBookingRepository(latency: fast);
      await booking.joinWaitlist(
        doctor: DoctorFixtures.byId('d1'),
        mode: ConsultationMode.video,
      );

      await expectLater(
        booking.joinWaitlist(
          doctor: DoctorFixtures.byId('d1'),
          mode: ConsultationMode.video,
        ),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'ALREADY_WAITING')),
      );
    });

    test('leaving stops the notification', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);
      final date = openDay();

      final free = (await booking.slotsFor(
        doctorId: 'd1',
        date: date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable);
      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d1'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      final entry = await booking.joinWaitlist(
        doctor: DoctorFixtures.byId('d1'),
        mode: ConsultationMode.video,
        preferredDate: date,
      );
      await booking.leaveWaitlist(entry.id);

      await appointments.cancel(booked.id, reason: 'Plans changed');

      final after =
          (await booking.waitlist()).firstWhere((e) => e.id == entry.id);
      expect(after.status, WaitlistStatus.cancelled,
          reason: 'a cancelled entry must not be flipped to notified');
    });
  });

  group('asking for a repeat prescription', () {
    Future<Prescription> anyIssued(
      FixturePrescriptionRepository prescriptions,
    ) async =>
        (await prescriptions.listForPatient()).firstWhere((p) => p.isValid);

    test('a request reaches the doctor and is not a prescription', () async {
      // The distinction the whole feature rests on: asking is not receiving.
      // A one-tap "reorder" would teach people that medicines arrive on
      // request, which is the expectation the MoHFW rules exist to prevent.
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      final before = (await prescriptions.listForPatient()).length;

      final request = await prescriptions.requestRefill(
        source.id,
        note: 'Ran out yesterday',
      );

      expect(request.status, RefillStatus.pending);
      expect(request.isOpen, isTrue);
      expect(request.patientNote, 'Ran out yesterday');
      expect((await prescriptions.listForPatient()).length, before,
          reason: 'nothing is issued until a doctor decides');
    });

    test('approving issues a new prescription, not a copy of the old one',
        () async {
      // A pharmacist dispensing against it is dispensing today. It needs its
      // own id, its own issue date and its own verification code.
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      final request = await prescriptions.requestRefill(source.id);

      final approved = await prescriptions.approveRefill(request.id);

      expect(approved.status, RefillStatus.approved);
      expect(approved.issuedPrescriptionId, isNotNull);
      expect(approved.issuedPrescriptionId, isNot(source.id));

      final issued = (await prescriptions.listForPatient())
          .firstWhere((p) => p.id == approved.issuedPrescriptionId);
      expect(issued.verificationCode, isNot(source.verificationCode));
      expect(issued.issuedAt.isAfter(source.issuedAt), isTrue);
      expect(issued.items.length, source.items.length);
    });

    test('declining without a note is refused', () async {
      // The rule this feature was asked for. A patient told only "declined"
      // cannot tell whether to book a review, wait, or stop taking the
      // medicine — so the fixture refuses a blank note and the UI cannot be
      // built against a laxer contract than the server's.
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      final request = await prescriptions.requestRefill(source.id);

      await expectLater(
        prescriptions.declineRefill(
          request.id,
          reason: RefillDeclineReason.tooSoon,
          note: '   ',
        ),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'DECLINE_REASON_REQUIRED')),
      );

      // Still open, so the doctor can answer properly.
      final still = FixtureBackend.shared.refillRequestById(request.id);
      expect(still.isOpen, isTrue);
    });

    test('a decline carries both a category and a note the patient can read',
        () async {
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      final request = await prescriptions.requestRefill(source.id);

      final declined = await prescriptions.declineRefill(
        request.id,
        reason: RefillDeclineReason.reviewNeeded,
        note: 'Please book a review first — it has been six months.',
      );

      expect(declined.status, RefillStatus.declined);
      expect(declined.declineReason, RefillDeclineReason.reviewNeeded);
      expect(declined.decisionNote, isNotEmpty);
      // The category is what tells the patient what to do next.
      expect(declined.declineReason!.label, isNotEmpty);
    });

    test('only one open request per prescription', () async {
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      await prescriptions.requestRefill(source.id);

      await expectLater(
        prescriptions.requestRefill(source.id),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'REFILL_ALREADY_REQUESTED')),
      );
    });

    test('but a new one may be asked once the last was answered', () async {
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      final first = await prescriptions.requestRefill(source.id);
      await prescriptions.declineRefill(
        first.id,
        reason: RefillDeclineReason.tooSoon,
        note: 'Try again next month.',
      );

      final second = await prescriptions.requestRefill(source.id);
      expect(second.isOpen, isTrue);
    });

    test('a decided request cannot be decided again', () async {
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      final request = await prescriptions.requestRefill(source.id);
      await prescriptions.approveRefill(request.id);

      await expectLater(
        prescriptions.declineRefill(
          request.id,
          reason: RefillDeclineReason.other,
          note: 'Changed my mind.',
        ),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'REFILL_ALREADY_DECIDED')),
      );
    });

    test('a patient can withdraw a request the doctor has not answered',
        () async {
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      final request = await prescriptions.requestRefill(source.id);

      final cancelled = await prescriptions.cancelRefill(request.id);
      expect(cancelled.status, RefillStatus.cancelled);
      expect(cancelled.isOpen, isFalse);
    });

    test('the request appears in the shared list both sides read', () async {
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final source = await anyIssued(prescriptions);
      final request = await prescriptions.requestRefill(source.id);

      final all = await prescriptions.refillRequests();
      expect(all.map((r) => r.id), contains(request.id));
    });
  });

  group('a doctor can answer a rating', () {
    Future<Rating> published(FixtureRatingsRepository ratings) async {
      final all = await ratings.listOwn();
      final target = all.first;
      FixtureBackend.shared.moderateRating(target.id, RatingStatus.published);
      return (await ratings.listOwn()).firstWhere((r) => r.id == target.id);
    }

    test('a reply enters moderation rather than appearing', () async {
      // A reply is public text written by the party with the most incentive to
      // argue. Publishing it directly would walk it straight past the queue
      // that exists to catch a reply naming someone's condition.
      final ratings = FixtureRatingsRepository(latency: fast);
      final target = await published(ratings);

      final replied = await ratings.reply(target.id, reply: 'Thank you.');

      expect(replied.hasReply, isTrue);
      expect(replied.replyStatus, RatingStatus.pendingModeration);
      expect(replied.replyIsVisible, isFalse);
    });

    test('and becomes visible only once moderated', () async {
      final ratings = FixtureRatingsRepository(latency: fast);
      final target = await published(ratings);
      await ratings.reply(target.id, reply: 'Thank you.');

      FixtureBackend.shared
          .moderateRatingReply(target.id, RatingStatus.published);

      final after =
          (await ratings.listOwn()).firstWhere((r) => r.id == target.id);
      expect(after.replyIsVisible, isTrue);
    });

    test('a pending reply keeps the rating in the moderation queue', () async {
      // The failure this guards: adding a moderated field and forgetting the
      // queue that clears it, so every reply sits pending forever.
      final ratings = FixtureRatingsRepository(latency: fast);
      final target = await published(ratings);

      expect(
        FixtureBackend.shared.pendingRatings().map((r) => r.id),
        isNot(contains(target.id)),
        reason: 'the rating itself is already published',
      );

      await ratings.reply(target.id, reply: 'Thank you.');

      expect(
        FixtureBackend.shared.pendingRatings().map((r) => r.id),
        contains(target.id),
      );
    });

    test('only once', () async {
      final ratings = FixtureRatingsRepository(latency: fast);
      final target = await published(ratings);
      await ratings.reply(target.id, reply: 'Thank you.');

      await expectLater(
        ratings.reply(target.id, reply: 'And another thing.'),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'REPLY_NOT_ALLOWED')),
      );
    });

    test('never to a rating a moderator took down', () async {
      // Replying to a removed rating would surface, in the reply, the
      // substance of the thing that was removed.
      final ratings = FixtureRatingsRepository(latency: fast);
      final all = await ratings.listOwn();
      FixtureBackend.shared.moderateRating(all.first.id, RatingStatus.removed);

      await expectLater(
        ratings.reply(all.first.id, reply: 'That is unfair.'),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'REPLY_NOT_ALLOWED')),
      );
    });

    test('an empty or over-long reply is refused', () async {
      final ratings = FixtureRatingsRepository(latency: fast);
      final target = await published(ratings);

      await expectLater(
        ratings.reply(target.id, reply: '   '),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'REPLY_EMPTY')),
      );
      await expectLater(
        ratings.reply(target.id, reply: 'x' * (Rating.maxReplyLength + 1)),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'REPLY_TOO_LONG')),
      );
    });
  });

  group('the seed clock', () {
    // The fixture is relative to "now" so a demo never looks stale. That is
    // right for the app and wrong for anything that has to be reproducible,
    // which is why the clock can be pinned — and why pinning has to restore
    // itself, or one test date-locks every test after it in the same process.
    test('pinning makes the seed deterministic, and releases cleanly', () {
      final realTomorrow = FixtureSeed.at(1, 9, 0);

      final release = FixtureSeed.pinClock(DateTime(2026, 6, 17, 10, 30));
      addTearDown(release);

      expect(FixtureSeed.at(0, 9, 0), DateTime(2026, 6, 17, 9, 0));
      expect(FixtureSeed.at(1, 9, 0), DateTime(2026, 6, 18, 9, 0));
      // Same answer twice: a pinned clock does not drift mid-test.
      expect(FixtureSeed.at(1, 9, 0), DateTime(2026, 6, 18, 9, 0));

      release();
      expect(FixtureSeed.at(1, 9, 0).day, realTomorrow.day);
    });

    test('a pinned seed produces identical data on every reset', () {
      final release = FixtureSeed.pinClock(DateTime(2026, 6, 17, 10, 30));
      addTearDown(release);

      FixtureBackend.resetShared();
      final first = FixtureBackend.shared.appointments().map((a) => a.start);

      FixtureBackend.resetShared();
      final second = FixtureBackend.shared.appointments().map((a) => a.start);

      expect(first, orderedEquals(second));
    });
  });

  group('events reach the notification centre', () {
    test('booking files a reminder the patient can see', () async {
      final booking = FixtureBookingRepository(latency: fast);
      final notifications = FixtureNotificationRepository(latency: fast);
      final date = openDay();

      final before = (await notifications.list()).length;

      final free = (await booking.slotsFor(
        doctorId: 'd1',
        date: date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable);

      final booked = await booking.book(
        doctor: DoctorFixtures.byId('d1'),
        slot: free,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      final after = await notifications.list();
      expect(after.length, before + 1);
      expect(after.first.kind, NotificationKind.appointmentReminder);
      expect(after.first.targetId, booked.id);
      expect(after.first.isRead, isFalse);
    });

    test('a notification body never names a drug', () async {
      // The rule the whole feature is built around: these strings land on a
      // lock screen, and naming the medicine discloses the condition to
      // whoever is holding the phone.
      final prescriptions = FixturePrescriptionRepository(latency: fast);
      final notifications = FixtureNotificationRepository(latency: fast);

      final drug = FixturePrescriptionRepository.drugCatalogue
          .firstWhere((d) => d.telemedicineList == TelemedicineDrugList.listO);

      await prescriptions.issue(
        appointmentId: 'a2',
        patientName: 'Priya Sharma',
        patientAge: '34',
        patientGender: 'Female',
        isFollowUp: false,
        items: [
          PrescriptionItem(
            drugId: drug.id,
            drugName: drug.name,
            genericName: drug.genericName,
            strength: drug.commonStrengths.first,
            form: drug.form,
            frequency: '1-0-1',
            durationDays: 5,
          ),
        ],
      );

      final issued = (await notifications.list()).firstWhere(
        (n) => n.kind == NotificationKind.prescriptionIssued,
      );

      expect(issued.title, isNot(contains(drug.name)));
      expect(issued.body, isNot(contains(drug.name)));
      expect(issued.body, isNot(contains(drug.genericName)));
    });

    test('cancelling tells the patient, and cannot be switched off', () async {
      final appointments = FixtureAppointmentRepository(latency: fast);
      final notifications = FixtureNotificationRepository(latency: fast);

      // Everything optional turned off. The cancellation still arrives.
      await notifications.updatePreferences(
        const NotificationPreferences(
          enabled: {},
          quietHours: QuietHours.defaults,
        ),
      );

      final upcoming =
          (await appointments.listForPatient()).firstWhere((a) => a.canCancel);
      await appointments.cancel(upcoming.id, reason: 'Plans changed');

      final changed = (await notifications.list())
          .where((n) => n.kind == NotificationKind.appointmentChanged);
      expect(changed, isNotEmpty);
      expect(changed.first.targetId, upcoming.id);
    });

    test('a kind the user turned off is never filed at all', () async {
      // Not filtered at read time — not stored. A centre that fills up with
      // things the user asked not to receive is the toggle failing quietly.
      final records = FixtureRecordsRepository(latency: fast);
      final notifications = FixtureNotificationRepository(latency: fast);

      await notifications.updatePreferences(
        NotificationPreferences(
          enabled: NotificationKind.values
              .where((k) => k != NotificationKind.recordReady)
              .toSet(),
          quietHours: const QuietHours(startHour: 0, endHour: 0),
        ),
      );

      final before = (await notifications.list()).length;
      await records.upload(
        title: 'Blood work',
        type: RecordType.labReport,
        recordedAt: DateTime.now(),
        file: testFile(name: 'bloods.pdf'),
      );
      // Past the fixture's simulated scan delay.
      await Future<void>.delayed(const Duration(seconds: 4));

      final after = await notifications.list();
      expect(
        after.where((n) => n.kind == NotificationKind.recordReady),
        isEmpty,
      );
      expect(after.length, before);
    });

    test('marking read moves the unread count', () async {
      final notifications = FixtureNotificationRepository(latency: fast);

      final unread =
          (await notifications.list()).where((n) => !n.isRead).toList();
      expect(unread, isNotEmpty);

      await notifications.markRead(unread.first.id);
      final after = await notifications.list();
      expect(after.firstWhere((n) => n.id == unread.first.id).isRead, isTrue);

      await notifications.markAllRead();
      expect((await notifications.list()).where((n) => !n.isRead), isEmpty);
    });

    test('registering a device is recorded', () async {
      // Sample data has no push service behind it. Recording the call is what
      // lets the coordinator's sign-in and sign-out wiring be exercised
      // without one.
      final notifications = FixtureNotificationRepository(latency: fast);

      await notifications.registerDevice(
        token: 'a-token-long-enough',
        platform: 'android',
      );
      expect(
          FixtureBackend.shared.registeredDeviceToken, 'a-token-long-enough');

      await notifications.unregisterDevice();
      expect(FixtureBackend.shared.registeredDeviceToken, isNull);
    });
  });

  group('rescheduling moves the booking, not just the appointment', () {
    Future<
        ({
          FixtureBookingRepository booking,
          FixtureAppointmentRepository appointments,
          Appointment booked,
          AppointmentSlot original,
          DateTime date
        })> bookOne(String doctorId) async {
      final booking = FixtureBookingRepository(latency: fast);
      final appointments = FixtureAppointmentRepository(latency: fast);
      final date = openDay(from: 2);

      final free = (await booking.slotsFor(
        doctorId: doctorId,
        date: date,
        mode: ConsultationMode.video,
      ))
          .where((s) => s.isAvailable)
          .toList();

      final booked = await booking.book(
        doctor: DoctorFixtures.byId(doctorId),
        slot: free.first,
        mode: ConsultationMode.video,
        patientName: 'Priya Sharma',
      );

      return (
        booking: booking,
        appointments: appointments,
        booked: booked,
        original: free.first,
        date: date,
      );
    }

    test('the old slot returns to the pool and the new one leaves it',
        () async {
      final ctx = await bookOne('d1');

      final target = (await ctx.booking.slotsFor(
        doctorId: 'd1',
        date: ctx.date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable && s.id != ctx.original.id);

      await ctx.appointments.reschedule(
        ctx.booked.id,
        start: target.start,
        end: target.end,
      );

      final after = await ctx.booking.slotsFor(
        doctorId: 'd1',
        date: ctx.date,
        mode: ConsultationMode.video,
      );

      // Both halves matter. Freeing the old slot without taking the new one
      // double-books the doctor; taking the new one without freeing the old
      // one loses a bookable slot forever.
      expect(
          after.firstWhere((s) => s.id == ctx.original.id).isAvailable, isTrue);
      expect(after.firstWhere((s) => s.id == target.id).isAvailable, isFalse);
    });

    test('the appointment keeps its identity and reference code', () async {
      final ctx = await bookOne('d2');

      final target = (await ctx.booking.slotsFor(
        doctorId: 'd2',
        date: ctx.date,
        mode: ConsultationMode.video,
      ))
          .firstWhere((s) => s.isAvailable && s.id != ctx.original.id);

      final moved = await ctx.appointments.reschedule(
        ctx.booked.id,
        start: target.start,
        end: target.end,
      );

      expect(moved.id, ctx.booked.id);
      // The reference code is what the patient quoted to the clinic. A moved
      // appointment is the same appointment.
      expect(moved.referenceCode, ctx.booked.referenceCode);
      expect(moved.start, target.start);
      // Still upcoming: RESCHEDULED describes the booking that was left
      // behind, and stamping it here would drop this one out of the list.
      expect(moved.status.isUpcoming, isTrue);

      final list = await ctx.appointments.listForPatient();
      expect(list.where((a) => a.id == ctx.booked.id).length, 1);
      expect(list.firstWhere((a) => a.id == ctx.booked.id).start, target.start);
    });

    test('moving onto a taken slot is refused and changes nothing', () async {
      final ctx = await bookOne('d3');

      final free = (await ctx.booking.slotsFor(
        doctorId: 'd3',
        date: ctx.date,
        mode: ConsultationMode.video,
      ))
          .where((s) => s.isAvailable)
          .toList();

      // Someone else takes the time our patient is about to move to.
      final contested = free.first;
      await ctx.booking.book(
        doctor: DoctorFixtures.byId('d3'),
        slot: contested,
        mode: ConsultationMode.video,
        patientName: 'Someone Else',
      );

      await expectLater(
        ctx.appointments.reschedule(
          ctx.booked.id,
          start: contested.start,
          end: contested.end,
        ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'SLOT_TAKEN')),
      );

      // The original booking survives the failure. Losing the appointment you
      // already had is the one outcome a reschedule must never produce.
      final still = await ctx.appointments.byId(ctx.booked.id);
      expect(still.start, ctx.booked.start);
      expect(still.status.isUpcoming, isTrue);

      final slots = await ctx.booking.slotsFor(
        doctorId: 'd3',
        date: ctx.date,
        mode: ConsultationMode.video,
      );
      expect(slots.firstWhere((s) => s.id == ctx.original.id).isAvailable,
          isFalse);
    });

    test('moving to the time it already has is refused', () async {
      final ctx = await bookOne('d1');

      await expectLater(
        ctx.appointments.reschedule(
          ctx.booked.id,
          start: ctx.booked.start,
          end: ctx.booked.end,
        ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'SAME_SLOT')),
      );
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
