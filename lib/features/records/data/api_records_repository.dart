import '../../../core/error/failure.dart';
import '../../../core/files/blob_client.dart';
import '../../../core/files/file_picker_service.dart';
import '../../../core/network/api_client.dart';
import '../domain/medical_record.dart';
import 'records_repository.dart';

/// Records against the MiDoctor API.
///
/// Upload is three steps, not one, and the shape is dictated by where the bytes
/// go: `POST /v1/records` records the metadata and hands back a signed URL, the
/// client PUTs the file straight to object storage, and a server-side trigger
/// inspects it before anyone can read it. The API never touches the bytes —
/// a Cloud Function is billed twice for relaying them and caps out at 32 MB.
class ApiRecordsRepository implements RecordsRepository {
  ApiRecordsRepository(this._api, this._blobs);

  final ApiClient _api;
  final BlobClient _blobs;

  @override
  Future<List<MedicalRecord>> listOwn() async {
    final json = await _api.get<List<dynamic>>('/v1/records');
    return json
        .map((e) => MedicalRecord.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<MedicalRecord>> listGranted(String patientId) async {
    final json =
        await _api.get<List<dynamic>>('/v1/records/granted/$patientId');
    return json
        .map((e) => MedicalRecord.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
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
    final created = await _api.post<Map<String, dynamic>>(
      '/v1/records',
      body: {
        'title': title,
        'type': type.wire,
        // A record's date is a calendar fact about a study, but the API stores
        // an instant, so it is sent as one and normalised server-side.
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        'contentType': file.contentType,
        'sizeBytes': file.sizeBytes,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );

    final record = MedicalRecord.fromJson(
      created['record'] as Map<String, dynamic>,
    );
    final upload = created['upload'] as Map<String, dynamic>?;
    if (upload == null) {
      throw const Failure(
        kind: FailureKind.server,
        message: 'Could not start the upload. Please try again.',
        code: 'NO_UPLOAD_URL',
      );
    }

    // If this fails the metadata already exists, pending and unreadable. That
    // is the right way round: a record with no file is inert and gets collected,
    // whereas a file with no record would be an unattributed blob of PHI.
    await _blobs.put(
      url: upload['url'] as String,
      bytes: file.bytes,
      contentType: file.contentType,
      onProgress: onProgress,
    );

    return record;
  }

  @override
  Future<String> downloadUrl(String id) async {
    final json =
        await _api.get<Map<String, dynamic>>('/v1/records/$id/download');
    return json['url'] as String;
  }

  @override
  Future<void> delete(String id) =>
      _api.delete<Map<String, dynamic>>('/v1/records/$id');
}
