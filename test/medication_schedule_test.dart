import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_backend.dart';
import 'package:healthcare_mobile/features/medications/data/medication_repository.dart';
import 'package:healthcare_mobile/features/medications/domain/medication_schedule.dart';
import 'package:healthcare_mobile/features/prescriptions/domain/prescription.dart';

/// The dosing parser and the dose log.
///
/// The parser is the part worth testing hardest, because its failure mode is
/// not a crash. It is an app quietly telling somebody to take a drug at a
/// frequency no doctor wrote down, with the prescription on screen as apparent
/// authority for it — and the wrong answers all look completely ordinary.
void main() {
  const fast = Duration.zero;

  group('dosing notation', () {
    test('three-position notation is morning, afternoon, night', () {
      expect(DoseSchedule.parse('1-0-1').slots,
          [DoseSlot.morning, DoseSlot.night]);
      expect(DoseSchedule.parse('1-1-1').slots,
          [DoseSlot.morning, DoseSlot.afternoon, DoseSlot.night]);
      expect(DoseSchedule.parse('0-0-1').slots, [DoseSlot.night]);
      expect(DoseSchedule.parse('1-0-0').slots, [DoseSlot.morning]);
    });

    test('four-position notation adds an evening', () {
      // The fourth position is not decoration: a doctor writing the long form
      // is separating an evening dose from a bedtime one.
      expect(DoseSchedule.parse('1-0-1-1').slots,
          [DoseSlot.morning, DoseSlot.evening, DoseSlot.night]);
    });

    test('half doses still count as a dose', () {
      expect(DoseSchedule.parse('0.5-0-0.5').slots,
          [DoseSlot.morning, DoseSlot.night]);
    });

    test('all-zero notation is refused, not rendered as an empty course', () {
      expect(DoseSchedule.parse('0-0-0').isUnparsed, isTrue);
    });

    test('Latin abbreviations parse', () {
      expect(DoseSchedule.parse('OD').slots, [DoseSlot.morning]);
      expect(
          DoseSchedule.parse('BD').slots, [DoseSlot.morning, DoseSlot.night]);
      expect(DoseSchedule.parse('TDS').slots,
          [DoseSlot.morning, DoseSlot.afternoon, DoseSlot.night]);
      expect(DoseSchedule.parse('QID').slots.length, 4);
      expect(DoseSchedule.parse('HS').slots, [DoseSlot.night]);
    });

    test('an abbreviation does not fire inside a longer word', () {
      // "bedtime" contains "bd" only if the match is unanchored. It is one
      // dose at night, not two.
      expect(DoseSchedule.parse('At bedtime').slots, [DoseSlot.night]);
    });

    test('English phrases parse', () {
      expect(DoseSchedule.parse('Twice daily').slots,
          [DoseSlot.morning, DoseSlot.night]);
      expect(DoseSchedule.parse('Three times a day').slots.length, 3);
      expect(DoseSchedule.parse('Once daily').slots, [DoseSlot.morning]);
    });

    test('as-needed is understood, and correctly has no schedule', () {
      for (final text in ['SOS', 'PRN', 'As needed', 'When required']) {
        final schedule = DoseSchedule.parse(text);
        expect(schedule.asNeeded, isTrue, reason: text);
        expect(schedule.isScheduled, isFalse, reason: text);
        // Not the same as unparsed: this one was read correctly.
        expect(schedule.isUnparsed, isFalse, reason: text);
      }
    });

    test('a weekly dose is never turned into a daily one', () {
      // The case this rule exists for. "Once weekly" contains "once", so a
      // phrase table consulted first would schedule 60,000 IU of vitamin D
      // every morning instead of every Sunday.
      final weekly = DoseSchedule.parse('Once weekly');
      expect(weekly.isScheduled, isFalse);
      expect(weekly.isUnparsed, isTrue);
    });

    test('other non-daily intervals are refused too', () {
      for (final text in [
        'Alternate days',
        'Every other day',
        'Once a month',
        'Every 6 hours',
        'Twice weekly',
      ]) {
        expect(DoseSchedule.parse(text).isScheduled, isFalse, reason: text);
      }
    });

    test('anything unrecognised is refused rather than guessed at', () {
      for (final text in ['', '   ', 'as directed', 'taper', '2 puffs']) {
        expect(DoseSchedule.parse(text).isUnparsed, isTrue, reason: text);
      }
    });
  });

  group('a course', () {
    PrescriptionItem item({String frequency = '1-0-1', int days = 5}) =>
        PrescriptionItem(
          drugName: 'Metformin',
          genericName: 'Metformin hydrochloride',
          strength: '500 mg',
          form: 'Tablet',
          frequency: frequency,
          durationDays: days,
        );

    MedicationCourse course({int days = 5, String frequency = '1-0-1'}) =>
        MedicationCourse(
          prescriptionId: 'p1',
          itemIndex: 0,
          item: item(frequency: frequency, days: days),
          startedOn: DateTime(2026, 6, 1),
          schedule: DoseSchedule.parse(frequency),
          prescriberName: 'Dr Rajesh Kumar',
        );

    test('runs from the issue date for the duration, inclusive', () {
      final c = course(days: 5);
      expect(c.endsOn, DateTime(2026, 6, 5));
      expect(c.isActiveOn(DateTime(2026, 6, 1)), isTrue);
      expect(c.isActiveOn(DateTime(2026, 6, 5)), isTrue);
      expect(c.isActiveOn(DateTime(2026, 5, 31)), isFalse);
      expect(c.isActiveOn(DateTime(2026, 6, 6)), isFalse);
    });

    test('days remaining counts today', () {
      final c = course(days: 5);
      expect(c.daysRemainingOn(DateTime(2026, 6, 1)), 5);
      expect(c.daysRemainingOn(DateTime(2026, 6, 5)), 1);
      expect(c.daysRemainingOn(DateTime(2026, 6, 9)), 0);
    });

    test('cancelled and superseded prescriptions produce no courses', () {
      // A superseded prescription has been replaced by one carrying the
      // corrected dose. Expanding both would put two conflicting instructions
      // for the same drug on one screen.
      Prescription p(String id, PrescriptionStatus status) => Prescription(
            id: id,
            verificationCode: 'RX-$id',
            providerName: 'Dr Rajesh Kumar',
            providerQualification: 'MBBS',
            providerRegistrationNumber: 'KMC-41902',
            patientName: 'Priya Sharma',
            patientAge: '32',
            patientGender: 'Female',
            issuedAt: DateTime(2026, 6, 1),
            status: status,
            items: [item()],
          );

      final courses = MedicationCourse.fromPrescriptions([
        p('a', PrescriptionStatus.issued),
        p('b', PrescriptionStatus.cancelled),
        p('c', PrescriptionStatus.superseded),
        p('d', PrescriptionStatus.draft),
      ]);
      expect(courses.map((c) => c.prescriptionId), ['a']);
    });

    test('a dose id is derived, not generated', () {
      // The same reason slot lock ids are deterministic: two taps on a slow
      // connection must address one record, not log the same tablet twice.
      final a =
          ScheduledDose.idFor('p1#0', DateTime(2026, 6, 3), DoseSlot.night);
      final b =
          ScheduledDose.idFor('p1#0', DateTime(2026, 6, 3), DoseSlot.night);
      expect(a, b);
      expect(a, 'p1#0#2026-06-03#NIGHT');
    });
  });

  group('marking a dose', () {
    ScheduledDose dose(DateTime day) => ScheduledDose(
          course: MedicationCourse(
            prescriptionId: 'p1',
            itemIndex: 0,
            item: const PrescriptionItem(
              drugName: 'Metformin',
              genericName: 'Metformin hydrochloride',
              strength: '500 mg',
              form: 'Tablet',
              frequency: '1-0-1',
              durationDays: 30,
            ),
            startedOn: DateTime(2026, 6, 1),
            schedule: DoseSchedule.parse('1-0-1'),
            prescriberName: 'Dr Rajesh Kumar',
          ),
          day: day,
          slot: DoseSlot.morning,
        );

    // Explicit instants, not local wall-clock times. `canMarkAt` resolves the
    // day in IST, so a test written in the runner's local time answers
    // differently on a UTC CI box than on a laptop in India.
    test('today and the past are open, the future is not', () {
      final now = DateTime.utc(2026, 6, 10, 9); // 14:30 IST, 10 June
      expect(dose(DateTime(2026, 6, 10)).canMarkAt(now), isTrue);
      expect(dose(DateTime(2026, 6, 9)).canMarkAt(now), isTrue);
      expect(dose(DateTime(2026, 6, 11)).canMarkAt(now), isFalse);
    });

    test('the whole of today is open, not just the hours that have passed', () {
      // Somebody catching up on the morning tablet at 11pm is doing the honest
      // thing, and somebody ticking tonight's at 6pm because they are going
      // out is too.
      final late = DateTime.utc(2026, 6, 10, 17); // 22:30 IST, 10 June
      expect(dose(DateTime(2026, 6, 10)).canMarkAt(late), isTrue);
    });

    test("the day is India's, not the phone's", () {
      // The server records a dose against an IST day and refuses one that is
      // not due yet. A client on device-local time disagrees with it for
      // anyone off Indian time: at 00:30 in Tokyo it is still the previous
      // evening in India, and the app would offer a dose the server then
      // rejects with it visibly on screen.
      final tokyoJustAfterMidnight = DateTime.utc(2026, 6, 10, 15, 30);
      expect(istDayOf(tokyoJustAfterMidnight), DateTime(2026, 6, 10));
      expect(
        dose(DateTime(2026, 6, 11)).canMarkAt(tokyoJustAfterMidnight),
        isFalse,
        reason: 'the 11th has not started in India yet',
      );

      // And the boundary itself: 18:29:59 UTC is still the 10th in India,
      // 18:30 is the 11th.
      expect(
          istDayOf(DateTime.utc(2026, 6, 10, 18, 29)), DateTime(2026, 6, 10));
      expect(
          istDayOf(DateTime.utc(2026, 6, 10, 18, 30)), DateTime(2026, 6, 11));
    });
  });

  group('adherence', () {
    MedicationCourse course() => MedicationCourse(
          prescriptionId: 'p1',
          itemIndex: 0,
          item: const PrescriptionItem(
            drugName: 'Metformin',
            genericName: 'Metformin hydrochloride',
            strength: '500 mg',
            form: 'Tablet',
            frequency: '1-0-1',
            durationDays: 30,
          ),
          startedOn: DateTime(2026, 6, 1),
          schedule: DoseSchedule.parse('1-0-1'),
          prescriberName: 'Dr Rajesh Kumar',
        );

    ScheduledDose at(DateTime day, DoseSlot slot, DoseOutcome? outcome) =>
        ScheduledDose(
          course: course(),
          day: day,
          slot: slot,
          outcome: outcome,
        );

    test('a dose whose hour has not arrived is not yet missed', () {
      // Otherwise every course reads as failing all morning.
      final now = DateTime(2026, 6, 10, 9);
      final adherence = Adherence.of([
        at(DateTime(2026, 6, 10), DoseSlot.morning, DoseOutcome.taken),
        at(DateTime(2026, 6, 10), DoseSlot.night, null),
      ], now: now);

      expect(adherence.due, 1);
      expect(adherence.taken, 1);
      expect(adherence.missed, 0);
      expect(adherence.ratio, 1.0);
    });

    test('a skipped dose counts as due and not taken', () {
      final now = DateTime(2026, 6, 10, 23);
      final adherence = Adherence.of([
        at(DateTime(2026, 6, 10), DoseSlot.morning, DoseOutcome.taken),
        at(DateTime(2026, 6, 10), DoseSlot.night, DoseOutcome.skipped),
      ], now: now);

      expect(adherence.due, 2);
      expect(adherence.taken, 1);
      expect(adherence.missed, 1);
    });

    test('nothing due yet reads as no figure, not as zero percent', () {
      // "0%" would accuse somebody of missing a dose they were never meant to
      // have taken.
      final adherence = Adherence.of(
        [at(DateTime(2026, 6, 12), DoseSlot.morning, null)],
        now: DateTime(2026, 6, 10, 9),
      );
      expect(adherence.due, 0);
      expect(adherence.ratio, isNull);
    });
  });

  group('the dose log', () {
    setUp(FixtureBackend.resetShared);

    /// The seeded course that is still running.
    const courseId = 'p3#0';

    DateTime today() {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }

    test('a mark is recorded and read back', () async {
      final repo = FixtureMedicationRepository(latency: fast);
      expect(await repo.marksSince(today()), isEmpty);

      final mark = await repo.mark(
        courseId,
        day: today(),
        slot: DoseSlot.morning,
        outcome: DoseOutcome.taken,
      );

      expect(mark.courseId, courseId);
      expect(mark.outcome, DoseOutcome.taken);
      // The day the dose was due, kept apart from when it was ticked: "taken,
      // four hours late" and "taken on time" are different facts.
      expect(mark.day, today());
      expect(mark.markedAt.isAfter(today()), isTrue);

      final marks = await repo.marksSince(today());
      expect(marks.single.id, mark.id);
    });

    test('marking the same dose twice logs one tablet, not two', () async {
      final repo = FixtureMedicationRepository(latency: fast);
      await repo.mark(courseId,
          day: today(), slot: DoseSlot.morning, outcome: DoseOutcome.taken);
      await repo.mark(courseId,
          day: today(), slot: DoseSlot.morning, outcome: DoseOutcome.skipped);

      final marks = await repo.marksSince(today());
      expect(marks.length, 1);
      expect(marks.single.outcome, DoseOutcome.skipped);
    });

    test('a mark can be taken back', () async {
      final repo = FixtureMedicationRepository(latency: fast);
      await repo.mark(courseId,
          day: today(), slot: DoseSlot.morning, outcome: DoseOutcome.taken);
      await repo.clear(courseId, day: today(), slot: DoseSlot.morning);
      expect(await repo.marksSince(today()), isEmpty);
    });

    test('a dose that is not due yet cannot be ticked off', () async {
      // Recording tomorrow's tablet today produces a record indistinguishable
      // from one that actually happened.
      final repo = FixtureMedicationRepository(latency: fast);
      await expectLater(
        repo.mark(
          courseId,
          day: today().add(const Duration(days: 1)),
          slot: DoseSlot.morning,
          outcome: DoseOutcome.taken,
        ),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'DOSE_NOT_DUE')),
      );
    });

    test('a day outside the course is refused', () async {
      final repo = FixtureMedicationRepository(latency: fast);
      await expectLater(
        repo.mark(
          courseId,
          day: today().subtract(const Duration(days: 40)),
          slot: DoseSlot.morning,
          outcome: DoseOutcome.taken,
        ),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', 'DOSE_OUTSIDE_COURSE')),
      );
    });

    test('an unknown medicine on a real prescription is refused', () async {
      final repo = FixtureMedicationRepository(latency: fast);
      await expectLater(
        repo.mark(
          'p3#99',
          day: today(),
          slot: DoseSlot.morning,
          outcome: DoseOutcome.taken,
        ),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'COURSE_NOT_FOUND')),
      );
    });

    test('the log only reaches back as far as it is asked to', () async {
      final repo = FixtureMedicationRepository(latency: fast);
      final yesterday = today().subtract(const Duration(days: 1));
      await repo.mark(courseId,
          day: yesterday, slot: DoseSlot.morning, outcome: DoseOutcome.taken);

      expect(await repo.marksSince(today()), isEmpty);
      expect((await repo.marksSince(yesterday)).length, 1);
    });
  });
}
