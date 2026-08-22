import 'package:meta/meta.dart';

import '../../providers_search/domain/doctor.dart';

enum WaitlistStatus {
  waiting('WAITING'),

  /// A slot opened and the patient was told. Deliberately terminal: the entry
  /// has done its job, and leaving it active would ping the same person every
  /// time anyone cancels for the rest of the month.
  notified('NOTIFIED'),

  /// The date they were waiting for has passed.
  expired('EXPIRED'),

  cancelled('CANCELLED');

  const WaitlistStatus(this.wire);

  final String wire;

  static WaitlistStatus fromWire(String? wire) =>
      WaitlistStatus.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => WaitlistStatus.waiting,
      );

  String get label => switch (this) {
        WaitlistStatus.waiting => 'Waiting',
        WaitlistStatus.notified => 'A slot opened',
        WaitlistStatus.expired => 'Expired',
        WaitlistStatus.cancelled => 'Cancelled',
      };

  bool get isActive => this == WaitlistStatus.waiting;
}

/// A patient asking to be told when a doctor frees up.
///
/// ## Why this is not a booking
///
/// Being notified is **not** a reservation, and the notification says so. A
/// held slot would be the obvious alternative and is the wrong one: holding a
/// cancelled slot for the first person on a list means it sits empty while
/// they are asleep, on a train, or no longer interested — which is exactly the
/// waste a cancellation was supposed to recover. First come, first served, and
/// everyone waiting hears at once.
///
/// ## Why it ends when it fires
///
/// [WaitlistStatus.notified] is terminal. An entry that stayed active would
/// ping the same person every time anybody cancelled for the rest of the
/// month, and the third of those is where people turn notifications off — for
/// this app, that means turning off the appointment reminders too.
@immutable
class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.mode,
    required this.createdAt,
    required this.status,
    this.preferredDate,
    this.notifiedAt,
  });

  final String id;
  final String doctorId;

  /// Snapshot, so the entry still reads sensibly if the directory changes.
  final String doctorName;

  final ConsultationMode mode;
  final DateTime createdAt;
  final WaitlistStatus status;

  /// The day they want, or null for "any day".
  ///
  /// Optional because both are real: someone who needs a specific Tuesday and
  /// someone who will take the first thing going. A required date would turn
  /// the second person into a series of entries.
  final DateTime? preferredDate;

  final DateTime? notifiedAt;

  bool get isActive => status.isActive;

  /// How long an "any day" entry stays alive.
  ///
  /// Without a horizon the list only grows, and an entry from four months ago
  /// notifies somebody who has long since been seen elsewhere.
  static const openEndedLifetime = Duration(days: 30);

  /// Whether this entry should still be considered.
  bool isLiveAt(DateTime now) {
    if (!status.isActive) return false;
    final date = preferredDate;
    if (date != null) {
      // A date in the past cannot be matched by any future slot.
      return !DateTime(date.year, date.month, date.day)
          .isBefore(DateTime(now.year, now.month, now.day));
    }
    return now.difference(createdAt) < openEndedLifetime;
  }

  /// Whether a slot at [start] is one this entry is waiting for.
  bool matches({
    required String doctorId,
    required DateTime start,
    required ConsultationMode mode,
    required DateTime now,
  }) {
    if (this.doctorId != doctorId) return false;
    if (this.mode != mode) return false;
    if (!isLiveAt(now)) return false;
    // A slot that has already started helps nobody.
    if (!start.isAfter(now)) return false;

    final date = preferredDate;
    if (date == null) return true;
    return date.year == start.year &&
        date.month == start.month &&
        date.day == start.day;
  }

  WaitlistEntry copyWith({WaitlistStatus? status, DateTime? notifiedAt}) =>
      WaitlistEntry(
        id: id,
        doctorId: doctorId,
        doctorName: doctorName,
        mode: mode,
        createdAt: createdAt,
        status: status ?? this.status,
        preferredDate: preferredDate,
        notifiedAt: notifiedAt ?? this.notifiedAt,
      );

  factory WaitlistEntry.fromJson(Map<String, dynamic> json) => WaitlistEntry(
        id: json['id'] as String,
        doctorId: json['doctorId'] as String,
        doctorName: json['doctorName'] as String? ?? '',
        mode: ConsultationMode.fromWire(json['mode'] as String?),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        status: WaitlistStatus.fromWire(json['status'] as String?),
        preferredDate: json['preferredDate'] == null
            ? null
            : DateTime.parse(json['preferredDate'] as String).toLocal(),
        notifiedAt: json['notifiedAt'] == null
            ? null
            : DateTime.parse(json['notifiedAt'] as String).toLocal(),
      );
}
