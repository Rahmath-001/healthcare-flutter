import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/features/appointments/domain/appointment.dart';
import 'package:healthcare_mobile/features/appointments/domain/queue_position.dart';
import 'package:healthcare_mobile/features/providers_search/data/doctor_fixtures.dart';
import 'package:healthcare_mobile/features/providers_search/domain/doctor.dart';

/// Queue position.
///
/// Every case here is a way of being told the wrong number while waiting in a
/// clinic — counting someone who has gone home, ignoring someone who arrived
/// early, or promising a wait that has nothing behind it.
void main() {
  final day = DateTime(2026, 8, 24);

  Appointment appointment({
    required String id,
    required int hour,
    required AppointmentStatus status,
    String doctorId = 'd1',
    int minutes = 30,
  }) {
    final start = DateTime(day.year, day.month, day.day, hour);
    return Appointment(
      id: id,
      referenceCode: 'MD$id',
      doctor: DoctorFixtures.byId(doctorId),
      patientName: 'Patient $id',
      start: start,
      end: start.add(Duration(minutes: minutes)),
      mode: ConsultationMode.inPerson,
      status: status,
      paymentStatus: PaymentStatus.notRequired,
      feeInr: 500,
    );
  }

  test('an empty clinic puts you next', () {
    final mine = appointment(
      id: 'me',
      hour: 10,
      status: AppointmentStatus.checkedIn,
    );
    final q = QueuePosition.of(mine, [mine]);

    expect(q.aheadOfYou, 0);
    expect(q.isNext, isTrue);
    expect(q.estimatedWait, Duration.zero);
  });

  test('checked-in patients count regardless of their slot time', () {
    // Arriving early is what checking in means. A queue that only counted
    // earlier slots would under-count every busy clinic.
    final mine = appointment(
      id: 'me',
      hour: 10,
      status: AppointmentStatus.checkedIn,
    );
    final q = QueuePosition.of(mine, [
      mine,
      appointment(id: 'a', hour: 11, status: AppointmentStatus.checkedIn),
      appointment(id: 'b', hour: 12, status: AppointmentStatus.checkedIn),
    ]);

    expect(q.aheadOfYou, 2);
  });

  test('a later booking that has not arrived is not in front of you', () {
    final mine = appointment(
      id: 'me',
      hour: 10,
      status: AppointmentStatus.checkedIn,
    );
    final q = QueuePosition.of(mine, [
      mine,
      appointment(id: 'later', hour: 11, status: AppointmentStatus.confirmed),
    ]);

    expect(q.aheadOfYou, 0);
  });

  test('an earlier booking that has not arrived still is', () {
    final mine = appointment(
      id: 'me',
      hour: 11,
      status: AppointmentStatus.checkedIn,
    );
    final q = QueuePosition.of(mine, [
      mine,
      appointment(id: 'earlier', hour: 10, status: AppointmentStatus.confirmed),
    ]);

    expect(q.aheadOfYou, 1);
  });

  test('cancellations and no-shows drop out', () {
    // This is why a queue moves faster than the clock suggests, and counting
    // them is how a patient is told to wait for people who went home.
    final mine = appointment(
      id: 'me',
      hour: 12,
      status: AppointmentStatus.checkedIn,
    );
    final q = QueuePosition.of(mine, [
      mine,
      appointment(
          id: 'gone', hour: 10, status: AppointmentStatus.cancelledByPatient),
      appointment(
          id: 'absent', hour: 11, status: AppointmentStatus.noShowPatient),
      appointment(id: 'done', hour: 9, status: AppointmentStatus.completed),
    ]);

    expect(q.aheadOfYou, 0);
    expect(q.isNext, isTrue);
  });

  test('someone being seen is reported, not counted as waiting', () {
    final mine = appointment(
      id: 'me',
      hour: 11,
      status: AppointmentStatus.checkedIn,
    );
    final q = QueuePosition.of(mine, [
      mine,
      appointment(id: 'busy', hour: 10, status: AppointmentStatus.inProgress),
    ]);

    // Next in line, but the doctor is not free — telling this patient the
    // queue is empty would send them to the door.
    expect(q.aheadOfYou, 0);
    expect(q.isNext, isTrue);
    expect(q.someoneInProgress, isTrue);
    expect(q.estimatedWait, const Duration(minutes: 30));
  });

  test('another doctor\'s clinic is a different queue', () {
    final mine = appointment(
      id: 'me',
      hour: 11,
      status: AppointmentStatus.checkedIn,
    );
    final q = QueuePosition.of(mine, [
      mine,
      appointment(
        id: 'other',
        hour: 9,
        status: AppointmentStatus.checkedIn,
        doctorId: 'd2',
      ),
    ]);

    expect(q.aheadOfYou, 0);
  });

  test('another day is a different queue', () {
    final mine = appointment(
      id: 'me',
      hour: 11,
      status: AppointmentStatus.checkedIn,
    );
    final yesterday = Appointment(
      id: 'y',
      referenceCode: 'MDy',
      doctor: DoctorFixtures.byId('d1'),
      patientName: 'Yesterday',
      start: DateTime(2026, 8, 23, 9),
      end: DateTime(2026, 8, 23, 9, 30),
      mode: ConsultationMode.inPerson,
      status: AppointmentStatus.checkedIn,
      paymentStatus: PaymentStatus.notRequired,
      feeInr: 500,
    );

    expect(QueuePosition.of(mine, [mine, yesterday]).aheadOfYou, 0);
  });

  group('the estimate', () {
    test('is withheld until you have checked in', () {
      // Before check-in the queue is not what decides when you are seen; your
      // own slot time is. "About 40 minutes" for tomorrow's appointment is
      // worse than saying nothing.
      final mine = appointment(
        id: 'me',
        hour: 16,
        status: AppointmentStatus.confirmed,
      );
      final q = QueuePosition.of(mine, [
        mine,
        appointment(id: 'a', hour: 9, status: AppointmentStatus.checkedIn),
      ]);

      expect(q.aheadOfYou, 1);
      expect(q.estimatedWait, isNull);
    });

    test('uses the clinic\'s own slot length', () {
      final mine = appointment(
        id: 'me',
        hour: 10,
        status: AppointmentStatus.checkedIn,
        minutes: 15,
      );
      final q = QueuePosition.of(mine, [
        mine,
        appointment(
            id: 'a', hour: 9, status: AppointmentStatus.checkedIn, minutes: 15),
        appointment(
            id: 'b', hour: 9, status: AppointmentStatus.checkedIn, minutes: 15),
      ]);

      expect(q.estimatedWait, const Duration(minutes: 30));
    });

    test('rounds to five minutes', () {
      // The input is a guess. "27 minutes" invites someone to believe it.
      final mine = appointment(
        id: 'me',
        hour: 10,
        status: AppointmentStatus.checkedIn,
        minutes: 20,
      );
      final q = QueuePosition.of(mine, [
        mine,
        appointment(
            id: 'a', hour: 9, status: AppointmentStatus.checkedIn, minutes: 20),
      ]);

      expect(q.estimatedWait!.inMinutes % 5, 0);
    });

    test('a malformed slot does not produce an instant wait', () {
      // A zero-length slot would otherwise report a forty-person queue as no
      // wait at all.
      final start = DateTime(day.year, day.month, day.day, 10);
      final broken = Appointment(
        id: 'me',
        referenceCode: 'MDme',
        doctor: DoctorFixtures.byId('d1'),
        patientName: 'Me',
        start: start,
        end: start,
        mode: ConsultationMode.inPerson,
        status: AppointmentStatus.checkedIn,
        paymentStatus: PaymentStatus.notRequired,
        feeInr: 500,
      );
      final q = QueuePosition.of(broken, [
        broken,
        appointment(id: 'a', hour: 9, status: AppointmentStatus.checkedIn),
      ]);

      expect(q.averageConsultationMinutes, 15);
      expect(q.estimatedWait, const Duration(minutes: 15));
    });
  });
}
