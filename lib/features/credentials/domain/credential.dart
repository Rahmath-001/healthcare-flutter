import 'package:flutter/foundation.dart';

/// Documents a provider must supply before verification (FR-PROV-001).
///
/// Note what is absent: there is no "Aadhaar card" kind. Identity is proven via
/// DigiLocker or offline eKYC, from which only name, date of birth and the last
/// four digits are retained. Storing Aadhaar images would be a serious legal
/// liability under the Aadhaar Act and UIDAI regulations.
enum CredentialKind {
  degreeCertificate('DEGREE_CERTIFICATE'),
  medicalRegistration('MEDICAL_REGISTRATION'),
  identityProof('IDENTITY_PROOF'),
  hospitalAffiliation('HOSPITAL_AFFILIATION');

  const CredentialKind(this.wire);

  final String wire;

  static CredentialKind fromWire(String? wire) =>
      CredentialKind.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => CredentialKind.degreeCertificate,
      );

  String get label => switch (this) {
        CredentialKind.degreeCertificate => 'Degree certificate',
        CredentialKind.medicalRegistration => 'Medical registration',
        CredentialKind.identityProof => 'Identity verification',
        CredentialKind.hospitalAffiliation => 'Hospital affiliation letter',
      };

  String get helpText => switch (this) {
        CredentialKind.degreeCertificate =>
          'Your MBBS, MD or MS degree certificate.',
        CredentialKind.medicalRegistration =>
          'Your NMC or State Medical Council registration certificate.',
        CredentialKind.identityProof =>
          'Verified through DigiLocker. We store only your name, date of '
              'birth and the last 4 digits, never a copy of the document.',
        CredentialKind.hospitalAffiliation =>
          'A letter from the hospital or clinic confirming you practise there.',
      };

  /// Identity is verified through DigiLocker rather than a file upload, so it
  /// gets a different affordance in the UI.
  bool get isDigiLocker => this == CredentialKind.identityProof;
}

enum CredentialReviewStatus {
  notSubmitted('NOT_SUBMITTED'),

  /// Metadata exists but the file has not finished uploading or being checked.
  /// A reviewer never sees a document in this state.
  pendingUpload('PENDING_UPLOAD'),

  submitted('SUBMITTED'),
  underReview('UNDER_REVIEW'),
  accepted('ACCEPTED'),
  rejected('REJECTED');

  const CredentialReviewStatus(this.wire);

  final String wire;

  /// An unknown state counts as not submitted, so it can never satisfy the
  /// verification gate by accident.
  static CredentialReviewStatus fromWire(String? wire) =>
      CredentialReviewStatus.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => CredentialReviewStatus.notSubmitted,
      );

  String get label => switch (this) {
        CredentialReviewStatus.notSubmitted => 'Not submitted',
        CredentialReviewStatus.pendingUpload => 'Uploading',
        CredentialReviewStatus.submitted => 'Submitted',
        CredentialReviewStatus.underReview => 'Under review',
        CredentialReviewStatus.accepted => 'Verified',
        CredentialReviewStatus.rejected => 'Rejected',
      };
}

/// Structured rejection reasons (FR-PROV-003).
///
/// Codes rather than free text, so a rejection can be shown in the provider's
/// own language and counted for fraud analysis.
enum RejectionReasonCode {
  docIllegible('DOC_ILLEGIBLE'),
  docExpired('DOC_EXPIRED'),
  nameMismatch('NAME_MISMATCH'),
  nmcNotFound('NMC_NOT_FOUND'),
  nmcSuspended('NMC_SUSPENDED'),
  affiliationUnverifiable('AFFILIATION_UNVERIFIABLE'),
  suspectedForgery('SUSPECTED_FORGERY'),
  duplicateAccount('DUPLICATE_ACCOUNT'),
  incompleteSubmission('INCOMPLETE_SUBMISSION');

  const RejectionReasonCode(this.wire);

  final String wire;

  static RejectionReasonCode? fromWire(String? wire) {
    if (wire == null) return null;
    for (final v in RejectionReasonCode.values) {
      if (v.wire == wire) return v;
    }
    return null;
  }

  String get label => switch (this) {
        RejectionReasonCode.docIllegible => 'Document was not readable',
        RejectionReasonCode.docExpired => 'Document has expired',
        RejectionReasonCode.nameMismatch =>
          'Name does not match your verified identity',
        RejectionReasonCode.nmcNotFound =>
          'Registration number not found on the council register',
        RejectionReasonCode.nmcSuspended =>
          'Registration is not currently active',
        RejectionReasonCode.affiliationUnverifiable =>
          'We could not confirm your hospital affiliation',
        RejectionReasonCode.suspectedForgery =>
          'Document could not be authenticated',
        RejectionReasonCode.duplicateAccount =>
          'An account already exists for this registration number',
        RejectionReasonCode.incompleteSubmission =>
          'Some documents were missing',
      };
}

@immutable
class ProviderCredential {
  const ProviderCredential({
    required this.kind,
    required this.status,
    this.fileName,
    this.uploadedAt,
    this.reasonCode,
    this.reviewerNote,
  });

  final CredentialKind kind;
  final CredentialReviewStatus status;
  final String? fileName;
  final DateTime? uploadedAt;
  final RejectionReasonCode? reasonCode;
  final String? reviewerNote;

  factory ProviderCredential.fromJson(Map<String, dynamic> json) =>
      ProviderCredential(
        kind: CredentialKind.fromWire(json['kind'] as String?),
        status: CredentialReviewStatus.fromWire(json['status'] as String?),
        fileName: json['fileName'] as String?,
        uploadedAt: json['uploadedAt'] == null
            ? null
            : DateTime.parse(json['uploadedAt'] as String).toLocal(),
        reasonCode: RejectionReasonCode.fromWire(json['reasonCode'] as String?),
        reviewerNote: json['reviewerNote'] as String?,
      );

  /// A rejected document counts as not provided, and so does one still
  /// uploading — the submit gate reopens on its own rather than needing a reset.
  bool get isProvided =>
      status == CredentialReviewStatus.submitted ||
      status == CredentialReviewStatus.underReview ||
      status == CredentialReviewStatus.accepted;

  ProviderCredential copyWith({
    CredentialReviewStatus? status,
    String? fileName,
    DateTime? uploadedAt,
  }) =>
      ProviderCredential(
        kind: kind,
        status: status ?? this.status,
        fileName: fileName ?? this.fileName,
        uploadedAt: uploadedAt ?? this.uploadedAt,
        reasonCode: reasonCode,
        reviewerNote: reviewerNote,
      );
}

/// Everything that must be true before a provider may submit for review.
///
/// MFA is part of the gate, not an afterthought: an approved provider can issue
/// prescriptions and read patient records, so the account must be hard to take
/// over before it gains those powers.
@immutable
class VerificationChecklist {
  const VerificationChecklist({
    required this.credentials,
    required this.registrationNumber,
    required this.mfaEnrolled,
  });

  final List<ProviderCredential> credentials;
  final String? registrationNumber;
  final bool mfaEnrolled;

  factory VerificationChecklist.fromJson(Map<String, dynamic> json) =>
      VerificationChecklist(
        credentials: ((json['credentials'] as List<dynamic>?) ?? const [])
            .map((e) => ProviderCredential.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        registrationNumber: json['registrationNumber'] as String?,
        mfaEnrolled: json['mfaEnrolled'] as bool? ?? false,
      );

  bool get allDocumentsProvided => credentials.every((c) => c.isProvided);

  bool get hasRegistrationNumber {
    final n = registrationNumber?.trim();
    return n != null && n.isNotEmpty;
  }

  bool get canSubmit =>
      allDocumentsProvided && hasRegistrationNumber && mfaEnrolled;

  int get completedCount => [
        allDocumentsProvided,
        hasRegistrationNumber,
        mfaEnrolled,
      ].where((c) => c).length;

  static const totalSteps = 3;

  VerificationChecklist copyWith({
    List<ProviderCredential>? credentials,
    String? registrationNumber,
    bool? mfaEnrolled,
  }) =>
      VerificationChecklist(
        credentials: credentials ?? this.credentials,
        registrationNumber: registrationNumber ?? this.registrationNumber,
        mfaEnrolled: mfaEnrolled ?? this.mfaEnrolled,
      );
}
