import 'package:meta/meta.dart';

/// What a timeline entry is.
///
/// A closed set, because each kind decides two things: which icon and tone it
/// reads in, and — more importantly — whether it is something *this doctor
/// did* or something *the patient shared*. Those two have different
/// authorization stories and must not be presented as one undifferentiated
/// stream.
enum TimelineKind {
  /// A consultation with this doctor.
  appointment,

  /// A note this doctor wrote up.
  note,

  /// A prescription this doctor issued.
  prescription,

  /// A record the patient uploaded and shared under a consent grant.
  sharedRecord,
}

/// One dated thing in a patient's history with one doctor.
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.kind,
    required this.at,
    required this.title,
    this.subtitle,
    this.targetId,
  });

  final TimelineKind kind;
  final DateTime at;
  final String title;
  final String? subtitle;

  /// What tapping opens, where anything does.
  final String? targetId;

  /// Whether this entry exists because the doctor did something.
  ///
  /// The distinction the whole screen rests on. A doctor may always see their
  /// own clinical acts with a patient — they authored them, and a consultation
  /// note they wrote does not stop being theirs when a consent grant lapses.
  /// A record the *patient* uploaded is the patient's, and is visible only
  /// while a grant covers it.
  bool get isOwnAct => kind != TimelineKind.sharedRecord;
}

/// A patient's history with one doctor, newest first.
@immutable
class PatientTimeline {
  const PatientTimeline({
    required this.patientId,
    required this.patientName,
    required this.entries,
    required this.hasActiveGrant,
  });

  final String patientId;
  final String patientName;
  final List<TimelineEntry> entries;

  /// Whether a live consent grant covers this patient's own records.
  ///
  /// Rendered explicitly rather than inferred from an empty list. "They have
  /// not shared anything" and "your access has expired" are different facts,
  /// and showing the second as the first invites a doctor to conclude a
  /// patient has no history.
  final bool hasActiveGrant;

  bool get isEmpty => entries.isEmpty;

  List<TimelineEntry> get sharedRecords =>
      entries.where((e) => e.kind == TimelineKind.sharedRecord).toList();

  /// Groups entries by calendar day, newest day first, preserving order
  /// within the day.
  Map<DateTime, List<TimelineEntry>> get byDay {
    final sorted = [...entries]..sort((a, b) => b.at.compareTo(a.at));
    final out = <DateTime, List<TimelineEntry>>{};
    for (final e in sorted) {
      final day = DateTime(e.at.year, e.at.month, e.at.day);
      out.putIfAbsent(day, () => []).add(e);
    }
    return out;
  }
}
