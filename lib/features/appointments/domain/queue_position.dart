import 'package:meta/meta.dart';

import 'appointment.dart';

/// Where a patient stands in a doctor's queue for the day.
///
/// Derived rather than stored, and that is the whole design. A stored position
/// has to be recomputed and rewritten every time anyone checks in, is seen, or
/// cancels — and every missed recompute is a patient told they are third when
/// they are next. Deriving it from the appointments the app already holds means
/// it cannot be stale in a way the appointment list is not.
///
/// ## What "ahead of you" counts
///
/// Only people who are actually still waiting: checked in, or confirmed for an
/// earlier slot today. Someone already `inProgress` is being seen rather than
/// waiting, so they are excluded from the count but reported separately — a
/// patient who is next while the doctor is mid-consultation should be told the
/// doctor is busy, not that the queue is empty.
///
/// Cancellations and no-shows drop out entirely. They are the reason a queue
/// moves faster than the clock suggests.
@immutable
class QueuePosition {
  const QueuePosition({
    required this.aheadOfYou,
    required this.someoneInProgress,
    required this.isCheckedIn,
    required this.averageConsultationMinutes,
  });

  /// How many patients are still waiting before this one.
  final int aheadOfYou;

  /// Whether the doctor is currently with a patient.
  final bool someoneInProgress;

  /// Whether this patient has checked in themselves.
  final bool isCheckedIn;

  /// Used only for the estimate. Comes from the appointment's own slot length
  /// rather than a global constant, because a 15-minute follow-up clinic and a
  /// 30-minute first-consult clinic do not queue at the same rate.
  final int averageConsultationMinutes;

  bool get isNext => aheadOfYou == 0;

  /// A deliberately coarse estimate, or null when it would be dishonest.
  ///
  /// Null while the patient has not checked in: before that, the queue ahead of
  /// them is not yet the thing that decides when they are seen — their own slot
  /// time is. Showing "about 40 minutes" to someone whose appointment is at
  /// four o'clock tomorrow is worse than showing nothing.
  ///
  /// Rounded to five minutes because the input is a guess. "About 25 minutes"
  /// invites someone to leave the waiting room; "27 minutes" invites them to
  /// believe it.
  Duration? get estimatedWait {
    if (!isCheckedIn) return null;
    final consultations = aheadOfYou + (someoneInProgress ? 1 : 0);
    if (consultations == 0) return Duration.zero;
    final minutes = consultations * averageConsultationMinutes;
    return Duration(minutes: (minutes / 5).round() * 5);
  }

  /// Computes the position of [mine] among [sameDoctorSameDay].
  ///
  /// The caller supplies the day's list because only it knows how it was
  /// fetched — the provider has every patient, a patient has only their own and
  /// gets the counts from the server.
  static QueuePosition of(
    Appointment mine,
    List<Appointment> sameDoctorSameDay,
  ) {
    var ahead = 0;
    var inProgress = false;

    for (final other in sameDoctorSameDay) {
      if (other.id == mine.id) continue;
      if (other.doctor.id != mine.doctor.id) continue;
      if (!_sameDay(other.start, mine.start)) continue;

      switch (other.status) {
        case AppointmentStatus.inProgress:
          inProgress = true;
        case AppointmentStatus.checkedIn:
          // A checked-in patient is waiting regardless of their slot time:
          // arriving early is exactly what checking in means, and a queue that
          // ignored them would under-count every busy clinic.
          ahead++;
        case AppointmentStatus.confirmed:
          // Not yet arrived, so they only count if their slot is genuinely
          // before this one. Someone booked for later who has not checked in
          // is not in front of anybody.
          if (other.start.isBefore(mine.start)) ahead++;
        default:
          // Cancelled, completed, no-show, expired: not waiting.
          break;
      }
    }

    final slotMinutes = mine.end.difference(mine.start).inMinutes;

    return QueuePosition(
      aheadOfYou: ahead,
      someoneInProgress: inProgress,
      isCheckedIn: mine.status == AppointmentStatus.checkedIn,
      // Falls back to 15 for a zero-length or malformed slot rather than
      // producing an estimate of zero minutes per patient, which would report
      // a forty-person queue as an instant wait.
      averageConsultationMinutes: slotMinutes > 0 ? slotMinutes : 15,
    );
  }

  /// Parses the server's answer.
  ///
  /// The API returns **counts, never the other appointments**. A patient asking
  /// where they are in a queue has no business receiving the list it was
  /// derived from — that list is other people's names, times and doctors. The
  /// server runs the same derivation and sends four numbers.
  factory QueuePosition.fromJson(Map<String, dynamic> json) => QueuePosition(
        aheadOfYou: (json['aheadOfYou'] as num?)?.toInt() ?? 0,
        someoneInProgress: json['someoneInProgress'] as bool? ?? false,
        isCheckedIn: json['isCheckedIn'] as bool? ?? false,
        averageConsultationMinutes:
            (json['averageConsultationMinutes'] as num?)?.toInt() ?? 15,
      );

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
