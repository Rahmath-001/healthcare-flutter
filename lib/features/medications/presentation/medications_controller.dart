import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../domain/dose_mark.dart';
import '../domain/medication_schedule.dart';

/// The day the medicines screen is showing. Never in the future.
final medicationDayProvider = NotifierProvider<MedicationDayNotifier, DateTime>(
    MedicationDayNotifier.new);

class MedicationDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Moves by whole days, clamped at today.
  ///
  /// The clamp is here rather than in the widget so that no caller can put the
  /// screen on a date whose doses are not markable — the day strip would then
  /// render tick boxes that always refuse.
  void shift(int days) {
    final next = DateTime(state.year, state.month, state.day + days);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    state = next.isAfter(today) ? today : next;
  }
}

/// Every course from every issued prescription.
///
/// Reads `prescriptionRepositoryProvider`, which is the cached one — so the
/// list of what to take survives a lost signal, and the dose log does not need
/// to.
final medicationCoursesProvider =
    FutureProvider<List<MedicationCourse>>((ref) async {
  final prescriptions =
      await ref.watch(prescriptionRepositoryProvider).listForPatient();
  return MedicationCourse.fromPrescriptions(prescriptions);
});

/// The dose log, from far enough back to cover any adherence figure on screen.
final _doseMarksProvider = FutureProvider<Map<String, DoseMark>>((ref) async {
  final from = DateTime.now().subtract(const Duration(days: 90));
  final marks = await ref.watch(medicationRepositoryProvider).marksSince(from);
  return {for (final m in marks) m.id: m};
});

/// One day's medicines, split by whether they can be scheduled at all.
@immutable
class MedicationDay {
  const MedicationDay({
    required this.day,
    required this.bySlot,
    required this.unscheduled,
    required this.finished,
  });

  final DateTime day;

  /// Doses due on [day], grouped by slot in chronological order.
  final Map<DoseSlot, List<ScheduledDose>> bySlot;

  /// Courses that are active but have no clock behind them: taken as needed,
  /// or written in a way the app will not guess at. Shown with the doctor's own
  /// words and no tick box.
  final List<MedicationCourse> unscheduled;

  /// Courses whose last day has passed. Kept visible for a while rather than
  /// vanishing, because "did I finish that course?" is a question people ask.
  final List<MedicationCourse> finished;

  bool get isEmpty => bySlot.isEmpty && unscheduled.isEmpty && finished.isEmpty;

  int get dueCount => bySlot.values.fold(0, (n, list) => n + list.length);

  int get takenCount => bySlot.values.fold(
        0,
        (n, list) =>
            n + list.where((d) => d.outcome == DoseOutcome.taken).length,
      );
}

final medicationDayProviderFamily =
    FutureProvider.family<MedicationDay, DateTime>((ref, day) async {
  final courses = await ref.watch(medicationCoursesProvider.future);
  final marks = await ref.watch(_doseMarksProvider.future);
  final at = DateTime(day.year, day.month, day.day);

  final bySlot = <DoseSlot, List<ScheduledDose>>{};
  final unscheduled = <MedicationCourse>[];
  final finished = <MedicationCourse>[];

  for (final course in courses) {
    if (!course.isActiveOn(at)) {
      // Only the recently finished, so the list does not become a history of
      // every antibiotic somebody has ever been given.
      final ended = course.endsOn;
      if (at.difference(ended).inDays > 0 && at.difference(ended).inDays <= 7) {
        finished.add(course);
      }
      continue;
    }

    if (!course.schedule.isScheduled) {
      unscheduled.add(course);
      continue;
    }

    for (final slot in course.schedule.slots) {
      final mark = marks[ScheduledDose.idFor(course.id, at, slot)];
      bySlot.putIfAbsent(slot, () => []).add(ScheduledDose(
            course: course,
            day: at,
            slot: slot,
            outcome: mark?.outcome,
            markedAt: mark?.markedAt,
          ));
    }
  }

  return MedicationDay(
    day: at,
    bySlot: {
      // Enum order is chronological, so iterating the values sorts the day.
      for (final slot in DoseSlot.values)
        if (bySlot[slot] != null) slot: bySlot[slot]!,
    },
    unscheduled: unscheduled,
    finished: finished,
  );
});

/// Adherence over a whole course, from its first day to today.
final courseAdherenceProvider =
    FutureProvider.family<Adherence, String>((ref, courseId) async {
  final courses = await ref.watch(medicationCoursesProvider.future);
  final marks = await ref.watch(_doseMarksProvider.future);
  final course = courses.where((c) => c.id == courseId).firstOrNull;
  if (course == null || !course.schedule.isScheduled) {
    return const Adherence(taken: 0, due: 0);
  }

  final now = DateTime.now();
  final doses = <ScheduledDose>[];
  for (var day = course.startedOn;
      !day.isAfter(course.endsOn);
      day = DateTime(day.year, day.month, day.day + 1)) {
    for (final slot in course.schedule.slots) {
      final mark = marks[ScheduledDose.idFor(course.id, day, slot)];
      doses.add(ScheduledDose(
        course: course,
        day: day,
        slot: slot,
        outcome: mark?.outcome,
        markedAt: mark?.markedAt,
      ));
    }
  }
  return Adherence.of(doses, now: now);
});

/// Records an outcome, or clears one when [outcome] is null.
///
/// Tapping a dose that is already marked the same way undoes it — the tick is
/// a toggle, because a mis-tap on a phone in one hand has to be recoverable
/// and this is the patient's own account of their day, not a signed record.
Future<void> markDose(
  WidgetRef ref,
  ScheduledDose dose, {
  required DoseOutcome? outcome,
}) async {
  final repo = ref.read(medicationRepositoryProvider);
  if (outcome == null) {
    await repo.clear(dose.course.id, day: dose.day, slot: dose.slot);
  } else {
    await repo.mark(
      dose.course.id,
      day: dose.day,
      slot: dose.slot,
      outcome: outcome,
    );
  }
  ref.invalidate(_doseMarksProvider);
}
