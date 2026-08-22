import 'package:meta/meta.dart';

import 'medication_schedule.dart';

/// A patient saying what they did about one dose.
///
/// The only thing this feature persists. Courses, slots and adherence are all
/// derived from the prescription plus these marks, so a prescription that is
/// later cancelled takes its schedule with it and leaves no orphan reminders.
@immutable
class DoseMark {
  const DoseMark({
    required this.id,
    required this.courseId,
    required this.day,
    required this.slot,
    required this.outcome,
    required this.markedAt,
  });

  /// `<prescriptionId>#<itemIndex>#<yyyy-mm-dd>#<SLOT>`, from
  /// [ScheduledDose.idFor]. Deterministic so a repeated tap overwrites rather
  /// than logging the same tablet twice.
  final String id;

  final String courseId;

  /// The day the dose was *due*, not the day it was ticked. Somebody marking
  /// last night's tablet this morning is recording last night.
  final DateTime day;

  final DoseSlot slot;
  final DoseOutcome outcome;

  /// When the patient tapped. Kept distinct from [day] because "taken, four
  /// hours late" and "taken on time" are different facts, and only one of them
  /// is visible if the two are collapsed.
  final DateTime markedAt;

  factory DoseMark.fromJson(Map<String, dynamic> json) => DoseMark(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        day: DateTime.parse(json['day'] as String),
        slot: DoseSlot.fromWire(json['slot'] as String?),
        outcome: DoseOutcome.fromWire(json['outcome'] as String?),
        markedAt: DateTime.parse(json['markedAt'] as String).toLocal(),
      );
}
