import 'package:flutter/foundation.dart';

import '../../features/credentials/domain/credential.dart';

/// Where an application sits in the review pipeline.
///
/// Mirrors the server's `ProviderStatus`, narrowed to the values a reviewer can
/// actually see in a queue — an application that is still a draft has not been
/// submitted to anyone.
enum ProviderApplicationStatus {
  submitted('SUBMITTED', 'Awaiting review'),
  underReview('UNDER_REVIEW', 'Under review'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Rejected');

  const ProviderApplicationStatus(this.wire, this.label);

  final String wire;
  final String label;
}

/// One credential document as it appears to a reviewer.
@immutable
class ProviderApplicationDocument {
  const ProviderApplicationDocument({
    required this.id,
    required this.kind,
    required this.status,
    required this.uploadedAt,
    this.fileName,
    this.reasonCode,
    this.reviewerNote,
  });

  final String id;
  final CredentialKind kind;
  final CredentialReviewStatus status;
  final DateTime uploadedAt;
  final String? fileName;
  final RejectionReasonCode? reasonCode;
  final String? reviewerNote;

  ProviderApplicationDocument copyWith({
    CredentialReviewStatus? status,
    RejectionReasonCode? reasonCode,
    String? reviewerNote,
  }) =>
      ProviderApplicationDocument(
        id: id,
        kind: kind,
        status: status ?? this.status,
        uploadedAt: uploadedAt,
        fileName: fileName,
        reasonCode: reasonCode,
        reviewerNote: reviewerNote,
      );
}

/// A doctor's verification application, as the operator console sees it.
///
/// Lives in `core/fixtures` rather than under `lib/admin/` on purpose: the
/// *provider* app writes one of these when it submits credentials, and the
/// console reads it. Putting it in the console's folder would mean the mobile
/// app importing from `lib/admin/`, which is exactly the coupling the separate
/// entry point exists to prevent.
@immutable
class ProviderApplicationRecord {
  const ProviderApplicationRecord({
    required this.userId,
    required this.displayName,
    required this.status,
    required this.submittedAt,
    required this.documents,
    required this.mfaEnrolled,
    this.email,
    this.phone,
    this.registrationNumber,
  });

  final String userId;
  final String displayName;
  final ProviderApplicationStatus status;
  final DateTime submittedAt;
  final List<ProviderApplicationDocument> documents;
  final bool mfaEnrolled;
  final String? email;
  final String? phone;
  final String? registrationNumber;

  /// Every gate satisfied: documents accepted, a registration number, and MFA.
  bool get isApprovable =>
      documents.isNotEmpty &&
      documents.every((d) => d.status == CredentialReviewStatus.accepted) &&
      (registrationNumber?.isNotEmpty ?? false) &&
      mfaEnrolled;

  ProviderApplicationRecord copyWith({
    ProviderApplicationStatus? status,
    List<ProviderApplicationDocument>? documents,
  }) =>
      ProviderApplicationRecord(
        userId: userId,
        displayName: displayName,
        status: status ?? this.status,
        submittedAt: submittedAt,
        documents: documents ?? this.documents,
        mfaEnrolled: mfaEnrolled,
        email: email,
        phone: phone,
        registrationNumber: registrationNumber,
      );
}
