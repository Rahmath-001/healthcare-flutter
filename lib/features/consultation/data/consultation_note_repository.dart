import '../../../core/fixtures/fixture_backend.dart';
import '../../../core/network/api_client.dart';
import '../domain/consultation_note.dart';

/// The doctor's clinical note on a consultation.
///
/// Separate from `RecordsRepository` on purpose. A record is a *file* the
/// patient uploaded and a scanner cleared; a note is text a clinician authored
/// against a specific appointment, with a different author, a different
/// authorization rule, and an append-only lifecycle. Folding them together
/// would mean one upload path that sometimes means "scan this" and sometimes
/// means "this is evidence".
abstract class ConsultationNoteRepository {
  /// The note for one appointment, or null if none has been written.
  Future<ConsultationNote?> forAppointment(String appointmentId);

  /// Writes the note. One per appointment, and it cannot be rewritten.
  Future<ConsultationNote> write(
    String appointmentId, {
    required String body,
  });

  /// Appends a correction. Never replaces anything.
  Future<ConsultationNote> addAddendum(String noteId, {required String body});
}

class FixtureConsultationNoteRepository implements ConsultationNoteRepository {
  FixtureConsultationNoteRepository({
    this.latency = const Duration(milliseconds: 250),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  /// The provider persona the sample data signs in as.
  static const _authorName = 'Dr Anjali Rao';
  static const _authorRegistration = 'KMC/45219';

  @override
  Future<ConsultationNote?> forAppointment(String appointmentId) async {
    await Future<void>.delayed(latency);
    return _backend.noteForAppointment(appointmentId);
  }

  @override
  Future<ConsultationNote> write(
    String appointmentId, {
    required String body,
  }) async {
    await Future<void>.delayed(latency);
    return _backend.writeConsultationNote(
      appointmentId,
      body: body,
      // Author and registration number are snapshotted server-side from the
      // session in the real thing — a client that supplied them could sign a
      // note as somebody else.
      authorName: _authorName,
      authorRegistrationNumber: _authorRegistration,
    );
  }

  @override
  Future<ConsultationNote> addAddendum(
    String noteId, {
    required String body,
  }) async {
    await Future<void>.delayed(latency);
    return _backend.addNoteAddendum(
      noteId,
      body: body,
      authorName: _authorName,
    );
  }
}

class ApiConsultationNoteRepository implements ConsultationNoteRepository {
  ApiConsultationNoteRepository(this._api);

  final ApiClient _api;

  @override
  Future<ConsultationNote?> forAppointment(String appointmentId) async {
    final json = await _api.get<Map<String, dynamic>?>(
      '/v1/appointments/$appointmentId/note',
    );
    // A consultation with no note yet is an ordinary state, not a 404 the UI
    // has to interpret.
    if (json == null || json.isEmpty) return null;
    return ConsultationNote.fromJson(json);
  }

  @override
  Future<ConsultationNote> write(
    String appointmentId, {
    required String body,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/appointments/$appointmentId/note',
      // Only the text. The author, their registration number and the timestamp
      // are all taken from the session and the clock server-side: a note is a
      // signed clinical document, and every part of the signature a client
      // could supply is a part it could forge.
      body: {'body': body},
    );
    return ConsultationNote.fromJson(json);
  }

  @override
  Future<ConsultationNote> addAddendum(
    String noteId, {
    required String body,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/notes/$noteId/addendum',
      body: {'body': body},
    );
    return ConsultationNote.fromJson(json);
  }
}
