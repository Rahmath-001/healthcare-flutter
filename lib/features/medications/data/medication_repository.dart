import '../../../core/fixtures/fixture_backend.dart';
import '../../../core/network/api_client.dart';
import '../domain/dose_mark.dart';
import '../domain/medication_schedule.dart';

/// The dose log.
///
/// Deliberately narrow: it stores what the patient says about doses and
/// nothing else. There is no `listCourses` here because a course is not a
/// stored thing — it is `PrescriptionRepository`'s data read through
/// [MedicationCourse.fromPrescriptions]. Giving this repository its own copy of
/// the dosing instructions is how a cancelled prescription ends up still
/// reminding somebody to take a drug.
abstract class MedicationRepository {
  /// Marks on or after [from], midnight-aligned.
  ///
  /// Bounded rather than "all", because the log grows a row per dose per day
  /// forever and a patient on four long-term medicines generates ~1,500 a year.
  Future<List<DoseMark>> marksSince(DateTime from);

  /// Records an outcome. Overwrites any earlier mark for the same dose.
  Future<DoseMark> mark(
    String courseId, {
    required DateTime day,
    required DoseSlot slot,
    required DoseOutcome outcome,
  });

  /// Undoes a mark.
  ///
  /// A mis-tap has to be correctable: this is the patient's own account of
  /// their day, not a clinical record signed by anybody, and a tick that cannot
  /// be taken back turns a fat finger into a permanent claim about medication.
  Future<void> clear(String courseId,
      {required DateTime day, required DoseSlot slot});
}

class FixtureMedicationRepository implements MedicationRepository {
  FixtureMedicationRepository({
    this.latency = const Duration(milliseconds: 180),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<List<DoseMark>> marksSince(DateTime from) async {
    await Future<void>.delayed(latency);
    return _backend.doseMarksSince(from);
  }

  @override
  Future<DoseMark> mark(
    String courseId, {
    required DateTime day,
    required DoseSlot slot,
    required DoseOutcome outcome,
  }) async {
    await Future<void>.delayed(latency);
    return _backend.markDose(
      courseId,
      day: day,
      slot: slot,
      outcome: outcome,
    );
  }

  @override
  Future<void> clear(
    String courseId, {
    required DateTime day,
    required DoseSlot slot,
  }) async {
    await Future<void>.delayed(latency);
    _backend.clearDoseMark(courseId, day: day, slot: slot);
  }
}

class ApiMedicationRepository implements MedicationRepository {
  ApiMedicationRepository(this._api);

  final ApiClient _api;

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<DoseMark>> marksSince(DateTime from) async {
    final json = await _api.get<List<dynamic>>(
      '/v1/medications/doses',
      query: {'from': _day(from)},
    );
    return json
        .map((e) => DoseMark.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// The dose id as a **path segment**.
  ///
  /// A dose id contains `#`, which in a URL starts the fragment — and a
  /// fragment is never sent to the server. Interpolated raw, every request
  /// here silently addresses `/v1/medications/doses/<prescriptionId>` and the
  /// day and slot are lost on the client. Percent-encoding is what makes the
  /// id survive the trip; Express decodes `req.params.id` on the way in.
  static String _segment(String courseId, DateTime day, DoseSlot slot) =>
      Uri.encodeComponent(ScheduledDose.idFor(courseId, day, slot));

  @override
  Future<DoseMark> mark(
    String courseId, {
    required DateTime day,
    required DoseSlot slot,
    required DoseOutcome outcome,
  }) async {
    final json = await _api.put<Map<String, dynamic>>(
      // PUT on a deterministic id, not POST to a collection. The id is derived
      // from course, day and slot, so a retry after a dropped response is the
      // same write rather than a second tablet in the log.
      '/v1/medications/doses/${_segment(courseId, day, slot)}',
      body: {'outcome': outcome.wire},
    );
    return DoseMark.fromJson(json);
  }

  @override
  Future<void> clear(
    String courseId, {
    required DateTime day,
    required DoseSlot slot,
  }) =>
      _api.delete<Map<String, dynamic>>(
        '/v1/medications/doses/${_segment(courseId, day, slot)}',
      );
}
