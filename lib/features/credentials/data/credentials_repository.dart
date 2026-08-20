import '../../../core/error/failure.dart';
import '../../../core/files/file_picker_service.dart';
import '../../../core/fixtures/fixture_backend.dart';
import '../domain/credential.dart';

/// Provider credential submission and the MFA enrolment that gates it.
abstract class CredentialsRepository {
  Future<VerificationChecklist> checklist();

  /// Uploads a credential document.
  ///
  /// [file] carries the bytes — a path is not portable and an upload needs the
  /// content anyway. The name and size stay in the signature so a caller can
  /// describe a document it has not read into memory.
  Future<VerificationChecklist> uploadDocument({
    required CredentialKind kind,
    required String fileName,
    required int sizeBytes,
    PickedFile? file,
  });

  /// Runs the DigiLocker issued-documents flow.
  ///
  /// Returns only the minimal verified identity fields. No document image and
  /// no Aadhaar number is ever stored — see [CredentialKind.identityProof].
  Future<VerificationChecklist> verifyIdentityWithDigiLocker();

  Future<VerificationChecklist> setRegistrationNumber(String number);

  /// Begins TOTP enrolment, returning the shared secret and its otpauth URI.
  Future<({String secret, String otpauthUri})> beginMfaEnrolment();

  /// Confirms enrolment with a code from the authenticator, returning the
  /// single-use recovery codes.
  Future<List<String>> confirmMfaEnrolment(String code);

  /// Submits for supervisor review. Fails unless every gate is satisfied.
  Future<void> submitForReview();
}

class FixtureCredentialsRepository implements CredentialsRepository {
  FixtureCredentialsRepository({
    this.latency = const Duration(milliseconds: 400),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<VerificationChecklist> checklist() async {
    await Future<void>.delayed(latency);
    return _backend.checklist();
  }

  @override
  Future<VerificationChecklist> uploadDocument({
    required CredentialKind kind,
    required String fileName,
    required int sizeBytes,
    PickedFile? file,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (sizeBytes > 15 * 1024 * 1024) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Documents must be smaller than 15 MB.',
        code: 'FILE_TOO_LARGE',
      );
    }
    if (kind.isDigiLocker) {
      // Identity is DigiLocker-only. Accepting a file here would be accepting a
      // photograph of an ID document, which is the thing this design exists to
      // avoid storing.
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Identity is verified through DigiLocker, not by uploading '
            'a document.',
        code: 'NOT_UPLOADABLE',
      );
    }

    final current = _backend.checklist();
    return _backend.updateChecklist(
      current.copyWith(
        credentials: [
          for (final c in current.credentials)
            if (c.kind == kind)
              c.copyWith(
                status: CredentialReviewStatus.submitted,
                fileName: fileName,
                uploadedAt: DateTime.now(),
              )
            else
              c,
        ],
      ),
    );
  }

  @override
  Future<VerificationChecklist> verifyIdentityWithDigiLocker() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    // Only the minimal verified fields come back. No document image and no
    // Aadhaar number is stored, here or anywhere.
    final current = _backend.checklist();
    return _backend.updateChecklist(
      current.copyWith(
        credentials: [
          for (final c in current.credentials)
            if (c.kind == CredentialKind.identityProof)
              c.copyWith(
                status: CredentialReviewStatus.submitted,
                fileName: 'Verified via DigiLocker',
                uploadedAt: DateTime.now(),
              )
            else
              c,
        ],
      ),
    );
  }

  @override
  Future<VerificationChecklist> setRegistrationNumber(String number) async {
    await Future<void>.delayed(latency);

    final trimmed = number.trim().toUpperCase();
    if (trimmed.length < 4) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Enter your council registration number.',
        code: 'REGISTRATION_INVALID',
      );
    }

    return _backend.updateChecklist(
      _backend.checklist().copyWith(registrationNumber: trimmed),
    );
  }

  @override
  Future<({String secret, String otpauthUri})> beginMfaEnrolment() async {
    await Future<void>.delayed(latency);

    // A fixed secret, so the QR code stays stable across a hot reload while
    // somebody is part-way through scanning it with a real phone.
    const secret = 'JBSWY3DPEHPK3PXP';
    return (
      secret: secret,
      otpauthUri: 'otpauth://totp/MiDoctor:doctor%40example.com'
          '?secret=$secret&issuer=MiDoctor&algorithm=SHA1&digits=6&period=30',
    );
  }

  @override
  Future<List<String>> confirmMfaEnrolment(String code) async {
    await Future<void>.delayed(latency);

    // Any six digits are accepted: the fixture cannot verify a real TOTP
    // without the clock the authenticator used, and rejecting valid codes would
    // make the flow untestable. The server checks properly — see
    // `functions/src/api/credentials/totp.ts`.
    if (code.trim().length != 6 || int.tryParse(code.trim()) == null) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'That code is not right. Try the current one.',
        code: 'MFA_CODE_INVALID',
      );
    }

    _backend.updateChecklist(_backend.checklist().copyWith(mfaEnrolled: true));

    // Shown once and never retrievable, exactly as the server behaves.
    return const [
      'A4F2K-9QW1M',
      'B7H3L-2XR8N',
      'C1D5P-6ZT4V',
      'D9G8S-3YU7B',
      'E2J6W-8KM5H',
      'F5N1X-4CQ9D',
      'G8R4Z-7VL2K',
      'H3T7Y-1PB6M',
    ];
  }

  @override
  Future<void> submitForReview() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final checklist = _backend.checklist();
    if (!checklist.canSubmit) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Finish every step before submitting for review.',
        code: 'CHECKLIST_INCOMPLETE',
      );
    }

    // Files an application into the shared store, which is what makes it appear
    // in the operator console's queue. This is the join that turns two fixture
    // apps into one product: a doctor submitting on their phone becomes a
    // reviewer's task on the web.
    _backend.submitForReview(
      userId: 'u-provider',
      displayName: 'Dr Ananya Sharma',
      email: 'ananya.sharma@example.com',
    );
  }
}
