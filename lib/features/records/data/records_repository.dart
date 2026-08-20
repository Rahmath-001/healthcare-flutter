import '../../../core/error/failure.dart';
import '../../../core/fixtures/fixture_backend.dart';
import '../../../core/files/file_picker_service.dart';
import '../domain/medical_record.dart';

abstract class RecordsRepository {
  Future<List<MedicalRecord>> listOwn();

  /// Records a provider may read, resolved against an active consent grant.
  ///
  /// There is no "list all patient records" call by design: a provider's view
  /// is always the intersection of a patient's records and a live grant.
  Future<List<MedicalRecord>> listGranted(String patientId);

  /// Uploads a record and its file.
  ///
  /// Takes the bytes, not a path: a path is not portable across platforms, and
  /// an upload needs the content regardless. The returned record is `pending` —
  /// the file is unreadable until the server has inspected it.
  Future<MedicalRecord> upload({
    required String title,
    required RecordType type,
    required DateTime recordedAt,
    required PickedFile file,
    String? notes,
    void Function(int sent, int total)? onProgress,
  });

  /// A short-lived URL for reading the file.
  ///
  /// Minted per call rather than stored on the record: entitlement is re-checked
  /// and the read is logged every time, so a URL cached on the client would
  /// bypass both.
  Future<String> downloadUrl(String id);

  Future<void> delete(String id);
}

class FixtureRecordsRepository implements RecordsRepository {
  FixtureRecordsRepository({
    this.latency = const Duration(milliseconds: 350),
    FixtureBackend? backend,
    this.scanDuration = const Duration(seconds: 3),
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  /// How long an upload spends "being checked" before it becomes readable.
  ///
  /// Non-zero by default because that state is real — the server puts an upload
  /// in quarantine and a trigger promotes it — and a fixture that skipped it
  /// would leave the UI's most common failure mode untested. Tests pass
  /// [Duration.zero].
  final Duration scanDuration;

  @override
  Future<List<MedicalRecord>> listOwn() async {
    await Future<void>.delayed(latency);
    return _backend.records();
  }

  @override
  Future<List<MedicalRecord>> listGranted(String patientId) async {
    await Future<void>.delayed(latency);
    // Resolved against a live grant, and refused without one — the same shape
    // as the server, so the provider UI has to handle a real denial.
    return _backend.recordsVisibleTo(patientId);
  }

  @override
  Future<MedicalRecord> upload({
    required String title,
    required RecordType type,
    required DateTime recordedAt,
    required PickedFile file,
    String? notes,
    void Function(int sent, int total)? onProgress,
  }) async {
    await Future<void>.delayed(latency);
    onProgress?.call(file.sizeBytes, file.sizeBytes);

    return _backend.addRecord(
      title: title,
      type: type,
      recordedAt: recordedAt,
      fileName: file.name,
      sizeBytes: file.sizeBytes,
      contentType: file.contentType,
      notes: notes,
      scanDuration: scanDuration,
    );
  }

  @override
  Future<String> downloadUrl(String id) async {
    await Future<void>.delayed(latency);
    final record = _backend.recordById(id);
    if (!record.isReadable) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'This file is still being checked.',
        code: 'RECORD_NOT_READY',
      );
    }
    // No object storage behind the fixture; the seam is what matters here.
    return 'https://fixture.midoctor.invalid/records/$id';
  }

  @override
  Future<void> delete(String id) async {
    await Future<void>.delayed(latency);
    _backend.deleteRecord(id);
  }
}
