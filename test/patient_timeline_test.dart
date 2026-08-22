import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/features/provider_home/domain/patient_timeline.dart';

/// The provider-side patient timeline.
///
/// The distinction under test is the one the screen rests on: a doctor's own
/// clinical acts are theirs to see, and the patient's own records are visible
/// only while a consent grant covers them. Collapsing the two into one stream
/// is how a lapsed grant silently keeps showing somebody's uploads.
void main() {
  TimelineEntry entry(TimelineKind kind, DateTime at) =>
      TimelineEntry(kind: kind, at: at, title: kind.name, targetId: 'x');

  group('what a doctor may see', () {
    test('own acts are distinguished from what the patient shared', () {
      expect(entry(TimelineKind.appointment, DateTime(2026, 6, 1)).isOwnAct,
          isTrue);
      expect(entry(TimelineKind.note, DateTime(2026, 6, 1)).isOwnAct, isTrue);
      expect(entry(TimelineKind.prescription, DateTime(2026, 6, 1)).isOwnAct,
          isTrue);
      // The only kind that needs a live grant.
      expect(entry(TimelineKind.sharedRecord, DateTime(2026, 6, 1)).isOwnAct,
          isFalse);
    });

    test('a lapsed grant is a stated fact, not an empty list', () {
      // "They have not shared anything" and "your access has expired" are
      // different facts. Showing the second as the first invites a doctor to
      // conclude a patient has no history.
      final timeline = PatientTimeline(
        patientId: 'u1',
        patientName: 'Priya Sharma',
        hasActiveGrant: false,
        entries: [entry(TimelineKind.appointment, DateTime(2026, 6, 1))],
      );

      expect(timeline.hasActiveGrant, isFalse);
      expect(timeline.isEmpty, isFalse, reason: 'own acts survive');
      expect(timeline.sharedRecords, isEmpty);
    });
  });

  group('grouping', () {
    test('entries group by day, newest day first', () {
      final timeline = PatientTimeline(
        patientId: 'u1',
        patientName: 'Priya Sharma',
        hasActiveGrant: true,
        entries: [
          entry(TimelineKind.appointment, DateTime(2026, 6, 1, 9)),
          entry(TimelineKind.note, DateTime(2026, 6, 3, 14)),
          entry(TimelineKind.prescription, DateTime(2026, 6, 3, 9)),
        ],
      );

      final days = timeline.byDay.keys.toList();
      expect(days, [DateTime(2026, 6, 3), DateTime(2026, 6, 1)]);
      // Within a day, newest first as well.
      expect(
          timeline.byDay[DateTime(2026, 6, 3)]!.first.kind, TimelineKind.note);
      expect(timeline.byDay[DateTime(2026, 6, 3)]!.length, 2);
    });

    test('an entry at midnight lands on its own day, not the one before', () {
      final timeline = PatientTimeline(
        patientId: 'u1',
        patientName: 'Priya Sharma',
        hasActiveGrant: true,
        entries: [entry(TimelineKind.appointment, DateTime(2026, 6, 3))],
      );
      expect(timeline.byDay.keys.single, DateTime(2026, 6, 3));
    });
  });
}
