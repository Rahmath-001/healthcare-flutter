import '../../../core/error/failure.dart';
import '../../../core/files/blob_client.dart';
import '../../../core/files/file_picker_service.dart';
import '../../../core/network/api_client.dart';
import '../domain/credential.dart';
import 'credentials_repository.dart';

/// Provider credentials against the MiDoctor API.
///
/// Documents go through the same three-step upload as medical records, and the
/// same quarantine: a reviewer opening an attacker-supplied file is precisely
/// the attack this pipeline exists to prevent, and a reviewer is a higher-value
/// target than a patient.
///
/// The verification gate — every document present, registration number
/// recorded, MFA enrolled — is re-derived server-side on submit. The client's
/// copy of that rule only decides when to enable a button.
class ApiCredentialsRepository implements CredentialsRepository {
  ApiCredentialsRepository(this._api, this._blobs);

  final ApiClient _api;
  final BlobClient _blobs;

  @override
  Future<VerificationChecklist> checklist() async {
    final json = await _api.get<Map<String, dynamic>>('/v1/credentials');
    return VerificationChecklist.fromJson(json);
  }

  /// Uploads a credential document.
  ///
  /// The contract takes a name and a size for historical reasons; the bytes are
  /// what actually move, so [file] carries them. A `PENDING_UPLOAD` document
  /// does not satisfy the gate, which is why the checklist returned here can
  /// still show the step as incomplete.
  @override
  Future<VerificationChecklist> uploadDocument({
    required CredentialKind kind,
    required String fileName,
    required int sizeBytes,
    PickedFile? file,
  }) async {
    if (file == null) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Choose a file to upload.',
        code: 'NO_FILE',
      );
    }

    final created = await _api.post<Map<String, dynamic>>(
      '/v1/credentials/documents',
      body: {
        'kind': kind.wire,
        'fileName': file.name,
        'contentType': file.contentType,
        'sizeBytes': file.sizeBytes,
      },
    );

    final upload = created['upload'] as Map<String, dynamic>?;
    if (upload == null) {
      throw const Failure(
        kind: FailureKind.server,
        message: 'Could not start the upload. Please try again.',
        code: 'NO_UPLOAD_URL',
      );
    }

    await _blobs.put(
      url: upload['url'] as String,
      bytes: file.bytes,
      contentType: file.contentType,
    );

    // Re-read rather than trusting the response: the document only becomes
    // SUBMITTED once the server-side trigger has inspected the bytes, which has
    // not happened at the moment the PUT returns.
    return checklist();
  }

  @override
  Future<VerificationChecklist> verifyIdentityWithDigiLocker() async {
    await _api
        .post<Map<String, dynamic>>('/v1/credentials/identity/digilocker');
    return checklist();
  }

  @override
  Future<VerificationChecklist> setRegistrationNumber(String number) async {
    await _api.put<Map<String, dynamic>>(
      '/v1/credentials/registration-number',
      body: {'registrationNumber': number},
    );
    return checklist();
  }

  @override
  Future<({String secret, String otpauthUri})> beginMfaEnrolment() async {
    final json =
        await _api.post<Map<String, dynamic>>('/v1/credentials/mfa/begin');
    return (
      secret: json['secret'] as String,
      otpauthUri: json['otpauthUri'] as String,
    );
  }

  @override
  Future<List<String>> confirmMfaEnrolment(String code) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/credentials/mfa/confirm',
      body: {'code': code},
    );
    // Shown once and never retrievable — the server keeps only hashes.
    return ((json['recoveryCodes'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
  }

  @override
  Future<void> submitForReview() =>
      _api.post<Map<String, dynamic>>('/v1/credentials/submit');
}
