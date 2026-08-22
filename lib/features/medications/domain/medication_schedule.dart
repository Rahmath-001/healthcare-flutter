import 'package:meta/meta.dart';

import '../../prescriptions/domain/prescription.dart';

/// The calendar day in IST, as a date key.
///
/// The server records a dose against an **IST** day and refuses one that is
/// not due yet. A client using the device's local day therefore disagrees with
/// it for anyone whose phone is not on Indian time: at 00:30 in Tokyo it is
/// still the previous evening in India, so the app would offer tonight's dose
/// and the server would refuse it as "not due yet" — with the dose visibly on
/// screen.
///
/// India has one timezone and no DST, so a fixed offset is exact. This matches
/// the rule the booking code already follows for slots.
DateTime istDayOf(DateTime at) {
  final ist = at.toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(ist.year, ist.month, ist.day);
}

/// Today, in IST.
DateTime istToday() => istDayOf(DateTime.now());

/// When in the day a dose falls.
///
/// Four slots, because Indian dosing notation is written in three or four
/// positions (`1-0-1`, `1-0-0-1`) and a doctor writing the four-position form
/// means something by the extra one.
enum DoseSlot {
  morning('MORNING', 8),
  afternoon('AFTERNOON', 14),
  evening('EVENING', 18),
  night('NIGHT', 21);

  const DoseSlot(this.wire, this.defaultHour);

  final String wire;

  /// The hour a reminder for this slot fires.
  ///
  /// A default, not a clinical instruction. A prescription that says `1-0-1`
  /// specifies *how many* doses and roughly when, never "08:00" — so these
  /// hours are the app's guess at an ordinary day, and the UI says so rather
  /// than presenting them as the doctor's words.
  final int defaultHour;

  static DoseSlot fromWire(String? value) => DoseSlot.values.firstWhere(
        (s) => s.wire == value,
        orElse: () => DoseSlot.morning,
      );
}

/// How a dose turned out. Patient self-report, and nothing more.
///
/// This is the most misreadable field in the feature: a screen rendering
/// "92% adherence" beside a clinician's notes invites reading a tick-box as
/// evidence a tablet was swallowed. Every surface that shows it says whose
/// claim it is.
enum DoseOutcome {
  taken('TAKEN'),
  skipped('SKIPPED');

  const DoseOutcome(this.wire);

  final String wire;

  static DoseOutcome fromWire(String? value) => DoseOutcome.values.firstWhere(
        (o) => o.wire == value,
        orElse: () => DoseOutcome.taken,
      );
}

/// The dosing pattern read out of a prescription item's `frequency` text.
///
/// ## Why this can refuse
///
/// `frequency` is free text a doctor typed. Most of it is one of a handful of
/// conventions — `1-0-1`, `BD`, `Twice daily` — and those parse exactly. The
/// rest does not, and the only safe answer for the rest is **no schedule**.
///
/// Guessing would produce an app telling somebody to take a drug at a time no
/// doctor specified, at a frequency nobody wrote down, with the prescription on
/// screen as apparent authority for it. An unparsed frequency therefore renders
/// as the doctor's own words with no reminders attached — which is exactly what
/// a paper prescription does.
@immutable
class DoseSchedule {
  const DoseSchedule._(this.slots, {required this.asNeeded});

  /// The slots a dose falls in, in order. Empty when unparsed or as-needed.
  final List<DoseSlot> slots;

  /// `SOS` / `PRN` — take it when you need it.
  ///
  /// Distinct from unparsed: this *was* understood, and it correctly has no
  /// schedule. Reminding somebody four times a day about a painkiller they are
  /// meant to take only when in pain trains them to take more of it.
  final bool asNeeded;

  bool get isScheduled => slots.isNotEmpty;

  /// Neither a recognised pattern nor an explicit as-needed instruction.
  bool get isUnparsed => slots.isEmpty && !asNeeded;

  static const _unparsed = DoseSchedule._([], asNeeded: false);
  static const _asNeeded = DoseSchedule._([], asNeeded: true);

  /// Reads a `frequency` string. Never throws, and never guesses.
  factory DoseSchedule.parse(String frequency) {
    final text = frequency.trim().toLowerCase();
    if (text.isEmpty) return _unparsed;

    if (_asNeededWords.any(text.contains)) return _asNeeded;

    // Anything that is not a *daily* pattern is refused outright, and this
    // check comes first because the phrase table below would otherwise eat it:
    // "once weekly" contains "once", and scheduling 60,000 IU of vitamin D
    // every morning instead of every Sunday is an overdose the app would have
    // invented on its own. The model here has one repeat interval — a day —
    // so every other interval is somebody else's instruction to follow.
    if (_nonDailyWords.any(text.contains)) return _unparsed;

    // Positional notation: 1-0-1, 1-1-1, 0-0-1, 1-0-0-1, and the half-tablet
    // forms written as 0.5. Any non-zero quantity is one dose in that slot;
    // the app does not model half tablets, because the strength on the item is
    // what the pharmacist reads and splitting it is a decision at the dose.
    final positions = text.split(RegExp(r'\s*[-–—/]\s*'));
    if (positions.length == 3 || positions.length == 4) {
      final quantities = positions.map(double.tryParse).toList(growable: false);
      if (!quantities.contains(null)) {
        final order = positions.length == 3
            ? const [DoseSlot.morning, DoseSlot.afternoon, DoseSlot.night]
            : const [
                DoseSlot.morning,
                DoseSlot.afternoon,
                DoseSlot.evening,
                DoseSlot.night,
              ];
        final slots = <DoseSlot>[
          for (var i = 0; i < order.length; i++)
            if (quantities[i]! > 0) order[i],
        ];
        // "0-0-0" is not a dosing instruction, it is a typo. Refusing it beats
        // rendering a course with nothing in it to take.
        return slots.isEmpty
            ? _unparsed
            : DoseSchedule._(slots, asNeeded: false);
      }
    }

    for (final entry in _abbreviations.entries) {
      if (RegExp('(^|\\s)${entry.key}(\$|\\s|\\.)').hasMatch(text)) {
        return DoseSchedule._(entry.value, asNeeded: false);
      }
    }
    for (final entry in _phrases.entries) {
      if (text.contains(entry.key)) {
        return DoseSchedule._(entry.value, asNeeded: false);
      }
    }

    return _unparsed;
  }

  static const _asNeededWords = ['sos', 'prn', 'as needed', 'when required'];

  /// Intervals this app does not model, and will not approximate.
  static const _nonDailyWords = [
    'week',
    'alternate',
    'every other',
    'month',
    'fortnight',
    'stat',
    'hourly',
    'hours',
    'hrs',
  ];

  /// Latin abbreviations, matched on word boundaries so `bd` does not fire
  /// inside "bedtime".
  static const Map<String, List<DoseSlot>> _abbreviations = {
    'od': [DoseSlot.morning],
    'qd': [DoseSlot.morning],
    'hs': [DoseSlot.night],
    'nocte': [DoseSlot.night],
    'mane': [DoseSlot.morning],
    'bd': [DoseSlot.morning, DoseSlot.night],
    'bid': [DoseSlot.morning, DoseSlot.night],
    'tds': [DoseSlot.morning, DoseSlot.afternoon, DoseSlot.night],
    'tid': [DoseSlot.morning, DoseSlot.afternoon, DoseSlot.night],
    'qid': [
      DoseSlot.morning,
      DoseSlot.afternoon,
      DoseSlot.evening,
      DoseSlot.night,
    ],
  };

  static const Map<String, List<DoseSlot>> _phrases = {
    'four times': [
      DoseSlot.morning,
      DoseSlot.afternoon,
      DoseSlot.evening,
      DoseSlot.night,
    ],
    'three times': [DoseSlot.morning, DoseSlot.afternoon, DoseSlot.night],
    'thrice': [DoseSlot.morning, DoseSlot.afternoon, DoseSlot.night],
    'twice': [DoseSlot.morning, DoseSlot.night],
    'once': [DoseSlot.morning],
    'at night': [DoseSlot.night],
    'bedtime': [DoseSlot.night],
    'every morning': [DoseSlot.morning],
  };
}

/// One medicine from one prescription, over the days it is meant to be taken.
///
/// Derived, never stored: it is a view of a `PrescriptionItem` plus the
/// prescription's issue date. Storing it would create a second copy of the
/// dosing instruction that a cancelled or superseded prescription could not
/// reach.
@immutable
class MedicationCourse {
  const MedicationCourse({
    required this.prescriptionId,
    required this.itemIndex,
    required this.item,
    required this.startedOn,
    required this.schedule,
    required this.prescriberName,
  });

  final String prescriptionId;

  /// Position in the prescription's item list.
  ///
  /// The identity of a course together with the prescription id, because
  /// `PrescriptionItem` has no id of its own — it is a line on a document, and
  /// the same drug can legitimately appear twice at different strengths.
  final int itemIndex;

  final PrescriptionItem item;

  /// Midnight on the day the prescription was issued.
  final DateTime startedOn;

  final DoseSchedule schedule;
  final String prescriberName;

  /// Stable across devices and reloads, so a dose ticked on a phone is the
  /// same dose on a tablet.
  String get id => '$prescriptionId#$itemIndex';

  /// The last day of the course, inclusive.
  DateTime get endsOn => DateTime(
        startedOn.year,
        startedOn.month,
        startedOn.day + item.durationDays - 1,
      );

  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(startedOn) && !d.isAfter(endsOn);
  }

  /// Days left including today, floored at zero.
  int daysRemainingOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final remaining = endsOn.difference(d).inDays + 1;
    return remaining < 0 ? 0 : remaining;
  }

  /// Every issued prescription, expanded into its courses.
  ///
  /// Cancelled and superseded prescriptions are dropped: a superseded document
  /// has been replaced by a newer one carrying the corrected dose, and showing
  /// both would put two conflicting instructions for the same drug on one
  /// screen.
  static List<MedicationCourse> fromPrescriptions(
    Iterable<Prescription> prescriptions,
  ) {
    final courses = <MedicationCourse>[];
    for (final p in prescriptions) {
      if (p.status != PrescriptionStatus.issued) continue;
      for (var i = 0; i < p.items.length; i++) {
        courses.add(MedicationCourse(
          prescriptionId: p.id,
          itemIndex: i,
          item: p.items[i],
          startedOn:
              DateTime(p.issuedAt.year, p.issuedAt.month, p.issuedAt.day),
          schedule: DoseSchedule.parse(p.items[i].frequency),
          prescriberName: p.providerName,
        ));
      }
    }
    return courses;
  }
}

/// A dose on a specific day, and what the patient said about it.
@immutable
class ScheduledDose {
  const ScheduledDose({
    required this.course,
    required this.day,
    required this.slot,
    this.outcome,
    this.markedAt,
  });

  final MedicationCourse course;
  final DateTime day;
  final DoseSlot slot;

  /// Null while the dose is still open.
  final DoseOutcome? outcome;
  final DateTime? markedAt;

  /// Deterministic, for the same reason slot lock ids are: two taps on a slow
  /// connection address one document instead of writing two logs for one
  /// tablet.
  ///
  /// **Percent-encode this before putting it in a URL.** It contains `#`,
  /// which starts a fragment — and a fragment never leaves the client, so an
  /// unencoded id silently truncates the request to the prescription id alone.
  static String idFor(String courseId, DateTime day, DoseSlot slot) {
    final d = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    return '$courseId#$d#${slot.wire}';
  }

  String get id => idFor(course.id, day, slot);

  DateTime get dueAt =>
      DateTime(day.year, day.month, day.day, slot.defaultHour);

  bool get isMarked => outcome != null;

  ScheduledDose copyWith({DoseOutcome? outcome, DateTime? markedAt}) =>
      ScheduledDose(
        course: course,
        day: day,
        slot: slot,
        outcome: outcome ?? this.outcome,
        markedAt: markedAt ?? this.markedAt,
      );

  /// Whether this dose may be marked yet.
  ///
  /// A future dose cannot: ticking tomorrow's tablet today records something
  /// that has not happened, and the record is then indistinguishable from one
  /// that did. The whole of today is open regardless of the hour, because
  /// somebody catching up at 11pm is doing the honest thing.
  bool canMarkAt(DateTime now) => !day.isAfter(istDayOf(now));
}

/// How much of a course the patient reports having taken.
///
/// Counts only doses that are due — a course on day 3 of 10 is measured
/// against 3 days, not 10, or every course would read as failing until the day
/// it ended.
@immutable
class Adherence {
  const Adherence({required this.taken, required this.due});

  final int taken;
  final int due;

  /// Null rather than 0% when nothing is due yet: a course starting tomorrow
  /// has no adherence, and "0%" would accuse somebody of missing a dose they
  /// were never meant to have taken.
  double? get ratio => due == 0 ? null : taken / due;

  int get missed => due - taken < 0 ? 0 : due - taken;

  static Adherence of(
    Iterable<ScheduledDose> doses, {
    required DateTime now,
  }) {
    var taken = 0;
    var due = 0;
    for (final dose in doses) {
      // A dose whose hour has not arrived is not yet missed.
      if (dose.dueAt.isAfter(now)) continue;
      due++;
      if (dose.outcome == DoseOutcome.taken) taken++;
    }
    return Adherence(taken: taken, due: due);
  }
}
