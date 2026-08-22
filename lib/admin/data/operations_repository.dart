import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/session/user_role.dart';
import '../../features/credentials/domain/credential.dart';
import '../../features/support/domain/support_ticket.dart';

/// One applicant in the review queue.
@immutable
class ProviderApplication {
  const ProviderApplication({
    required this.userId,
    required this.providerStatus,
    this.displayName,
    this.email,
    this.phone,
    this.registrationNumber,
    this.submittedAt,
  });

  final String userId;
  final ProviderStatus providerStatus;
  final String? displayName;
  final String? email;
  final String? phone;
  final String? registrationNumber;
  final DateTime? submittedAt;

  factory ProviderApplication.fromJson(Map<String, dynamic> json) =>
      ProviderApplication(
        userId: json['userId'] as String,
        providerStatus:
            ProviderStatus.fromWire(json['providerStatus'] as String?),
        displayName: json['displayName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        registrationNumber: json['registrationNumber'] as String?,
        submittedAt: json['submittedAt'] == null
            ? null
            : DateTime.parse(json['submittedAt'] as String).toLocal(),
      );
}

/// One uploaded credential document, as a reviewer sees it.
@immutable
class ReviewDocument {
  const ReviewDocument({
    required this.id,
    required this.kind,
    required this.status,
    required this.hasFile,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadedAt,
    this.fileName,
    this.reasonCode,
    this.reviewerNote,
    this.reviewedBy,
  });

  final String id;
  final CredentialKind kind;
  final CredentialReviewStatus status;

  /// Whether there is anything to open. A document still in quarantine, or one
  /// that failed inspection, has no file — and the console must say so rather
  /// than presenting a button that 409s.
  final bool hasFile;

  final String contentType;
  final int sizeBytes;
  final DateTime uploadedAt;
  final String? fileName;
  final RejectionReasonCode? reasonCode;
  final String? reviewerNote;
  final String? reviewedBy;

  bool get isDecided =>
      status == CredentialReviewStatus.accepted ||
      status == CredentialReviewStatus.rejected;

  factory ReviewDocument.fromJson(Map<String, dynamic> json) => ReviewDocument(
        id: json['id'] as String,
        kind: CredentialKind.fromWire(json['kind'] as String?),
        status: CredentialReviewStatus.fromWire(json['status'] as String?),
        hasFile: json['hasFile'] as bool? ?? false,
        contentType: json['contentType'] as String? ?? 'application/pdf',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        uploadedAt: DateTime.parse(json['uploadedAt'] as String).toLocal(),
        fileName: json['fileName'] as String?,
        reasonCode: RejectionReasonCode.fromWire(json['reasonCode'] as String?),
        reviewerNote: json['reviewerNote'] as String?,
        reviewedBy: json['reviewedBy'] as String?,
      );
}

/// Everything a reviewer needs about one applicant.
@immutable
class ProviderDossier {
  const ProviderDossier({
    required this.userId,
    required this.providerStatus,
    required this.accountStatus,
    required this.mfaEnrolled,
    required this.documents,
    this.displayName,
    this.email,
    this.phone,
    this.registrationNumber,
    this.identityVerifiedAt,
  });

  final String userId;
  final ProviderStatus providerStatus;
  final AccountStatus accountStatus;
  final bool mfaEnrolled;
  final List<ReviewDocument> documents;
  final String? displayName;
  final String? email;
  final String? phone;
  final String? registrationNumber;
  final DateTime? identityVerifiedAt;

  /// Whether every gate is satisfied.
  ///
  /// Mirrors the server's check so the console can explain *why* approval is
  /// unavailable rather than presenting a button that fails. The server decides.
  bool get isApprovable =>
      documents.isNotEmpty &&
      documents.every((d) => d.status == CredentialReviewStatus.accepted) &&
      (registrationNumber?.isNotEmpty ?? false) &&
      mfaEnrolled;

  List<String> get outstanding => [
        for (final d in documents)
          if (d.status != CredentialReviewStatus.accepted)
            '${d.kind.label} — ${d.status.label.toLowerCase()}',
        if (registrationNumber == null || registrationNumber!.isEmpty)
          'No council registration number',
        if (!mfaEnrolled) 'Two-factor authentication not enrolled',
      ];

  factory ProviderDossier.fromJson(Map<String, dynamic> json) =>
      ProviderDossier(
        userId: json['userId'] as String,
        providerStatus:
            ProviderStatus.fromWire(json['providerStatus'] as String?),
        accountStatus: AccountStatus.fromWire(json['accountStatus'] as String?),
        mfaEnrolled: json['mfaEnrolled'] as bool? ?? false,
        documents: ((json['documents'] as List<dynamic>?) ?? const [])
            .map((e) => ReviewDocument.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        displayName: json['displayName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        registrationNumber: json['registrationNumber'] as String?,
        identityVerifiedAt: json['identityVerifiedAt'] == null
            ? null
            : DateTime.parse(json['identityVerifiedAt'] as String).toLocal(),
      );
}

/// A rating awaiting moderation.
@immutable
class PendingRating {
  const PendingRating({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.stars,
    required this.createdAt,
    this.comment,
    this.editedAt,
    this.providerReply,
    this.replyStatus,
  });

  final String id;
  final String doctorId;
  final String doctorName;
  final int stars;
  final DateTime createdAt;
  final String? comment;

  /// The doctor's reply, when there is one awaiting a decision.
  ///
  /// Carried here so a moderator sees the text they are ruling on. A queue that
  /// showed only "this rating has a reply" would be asking someone to approve
  /// words they cannot read.
  final String? providerReply;
  final String? replyStatus;

  bool get replyNeedsModeration =>
      providerReply != null && replyStatus == 'PENDING_MODERATION';
  final DateTime? editedAt;

  factory PendingRating.fromJson(Map<String, dynamic> json) => PendingRating(
        id: json['id'] as String,
        doctorId: json['doctorId'] as String,
        doctorName: json['doctorName'] as String,
        stars: (json['stars'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        comment: json['comment'] as String?,
        editedAt: json['editedAt'] == null
            ? null
            : DateTime.parse(json['editedAt'] as String).toLocal(),
        providerReply: json['providerReply'] as String?,
        replyStatus: json['replyStatus'] as String?,
      );
}

/// A ticket in the agent queue.
@immutable
class QueuedTicket {
  const QueuedTicket({
    required this.id,
    required this.reference,
    required this.subject,
    required this.category,
    required this.status,
    required this.updatedAt,
    required this.messageCount,
    this.assignedTo,
  });

  final String id;
  final String reference;
  final String subject;
  final TicketCategory category;
  final TicketStatus status;
  final DateTime updatedAt;
  final int messageCount;
  final String? assignedTo;

  factory QueuedTicket.fromJson(Map<String, dynamic> json) => QueuedTicket(
        id: json['id'] as String,
        reference: json['reference'] as String,
        subject: json['subject'] as String,
        category: TicketCategory.fromWire(json['category'] as String?),
        status: TicketStatus.fromWire(json['status'] as String?),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
        messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
        assignedTo: json['assignedTo'] as String?,
      );
}

/// Everything the operator console can do.
///
/// One repository rather than five, because the console is one tool and the
/// endpoints behind it are all reviewer-side. Splitting it would imply the
/// pieces are independently useful, and they are not.
abstract class OperationsRepository {
  Future<List<ProviderApplication>> reviewQueue();
  Future<ProviderDossier> dossier(String userId);
  Future<void> claimForReview(String userId);

  /// A short-lived URL for one credential document. Minted per open, and logged.
  Future<String> documentUrl(String credentialId);

  Future<void> decideDocument(
    String credentialId, {
    required bool accept,
    RejectionReasonCode? reasonCode,
    String? note,
  });

  Future<void> approveProvider(String userId,
      {required Map<String, dynamic> profile});
  Future<void> rejectProvider(String userId, {required String reason});

  Future<void> suspendAccount(
    String userId, {
    required AccountStatus status,
    required String reason,
  });
  Future<void> reactivateAccount(String userId);
  Future<void> assignRole(String userId, UserRole role);
  Future<Map<String, dynamic>> lookupUser(String userId);

  Future<List<PendingRating>> pendingRatings();
  Future<void> moderateRating(String id, {required String status});

  /// Moderates the doctor's reply, separately from the rating.
  ///
  /// Separate because they are separate texts by separate authors: a fair
  /// rating can attract a reply that names a diagnosis, and hiding the
  /// patient's words to suppress the doctor's would punish the wrong person.
  Future<void> moderateRatingReply(String id, {required String status});

  Future<List<QueuedTicket>> ticketQueue({TicketStatus? status});
  Future<SupportTicket> ticket(String id);
  Future<void> replyToTicket(String id, String body);
  Future<void> setTicketStatus(String id, TicketStatus status);
}

class ApiOperationsRepository implements OperationsRepository {
  ApiOperationsRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ProviderApplication>> reviewQueue() async {
    final json = await _api.get<List<dynamic>>('/v1/provider/queue');
    return json
        .map((e) => ProviderApplication.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<ProviderDossier> dossier(String userId) async {
    final json =
        await _api.get<Map<String, dynamic>>('/v1/review/providers/$userId');
    return ProviderDossier.fromJson(json);
  }

  @override
  Future<void> claimForReview(String userId) =>
      _api.post<Map<String, dynamic>>('/v1/review/providers/$userId/claim');

  @override
  Future<String> documentUrl(String credentialId) async {
    final json = await _api.get<Map<String, dynamic>>(
        '/v1/review/credentials/$credentialId/download');
    return json['url'] as String;
  }

  @override
  Future<void> decideDocument(
    String credentialId, {
    required bool accept,
    RejectionReasonCode? reasonCode,
    String? note,
  }) =>
      _api.post<Map<String, dynamic>>(
        '/v1/review/credentials/$credentialId/decision',
        body: {
          'decision': accept ? 'ACCEPT' : 'REJECT',
          if (reasonCode != null) 'reasonCode': reasonCode.wire,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );

  @override
  Future<void> approveProvider(
    String userId, {
    required Map<String, dynamic> profile,
  }) =>
      _api.post<Map<String, dynamic>>(
        '/v1/provider/$userId/approve',
        body: {'profile': profile},
      );

  @override
  Future<void> rejectProvider(String userId, {required String reason}) =>
      _api.post<Map<String, dynamic>>(
        '/v1/provider/$userId/reject',
        body: {'reason': reason},
      );

  @override
  Future<void> suspendAccount(
    String userId, {
    required AccountStatus status,
    required String reason,
  }) =>
      _api.post<Map<String, dynamic>>(
        '/v1/admin/users/$userId/suspend',
        body: {'status': status.wire, 'reason': reason},
      );

  @override
  Future<void> reactivateAccount(String userId) =>
      _api.post<Map<String, dynamic>>('/v1/admin/users/$userId/reactivate');

  @override
  Future<void> assignRole(String userId, UserRole role) =>
      _api.post<Map<String, dynamic>>(
        '/v1/admin/users/$userId/role',
        body: {'role': role.wire},
      );

  @override
  Future<Map<String, dynamic>> lookupUser(String userId) =>
      _api.get<Map<String, dynamic>>('/v1/admin/users/$userId');

  @override
  Future<List<PendingRating>> pendingRatings() async {
    final json = await _api.get<List<dynamic>>('/v1/review/ratings/pending');
    return json
        .map((e) => PendingRating.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> moderateRating(String id, {required String status}) =>
      _api.post<Map<String, dynamic>>(
        '/v1/ratings/$id/moderate',
        body: {'status': status},
      );

  @override
  Future<void> moderateRatingReply(String id, {required String status}) =>
      _api.post<Map<String, dynamic>>(
        '/v1/ratings/$id/reply/moderate',
        body: {'status': status},
      );

  @override
  Future<List<QueuedTicket>> ticketQueue({TicketStatus? status}) async {
    final json = await _api.get<List<dynamic>>(
      '/v1/review/support/tickets',
      query: {if (status != null) 'status': status.wire},
    );
    return json
        .map((e) => QueuedTicket.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<SupportTicket> ticket(String id) async {
    final json =
        await _api.get<Map<String, dynamic>>('/v1/review/support/tickets/$id');
    return SupportTicket.fromJson(json);
  }

  @override
  Future<void> replyToTicket(String id, String body) =>
      _api.post<Map<String, dynamic>>(
        '/v1/review/support/tickets/$id/replies',
        body: {'body': body},
      );

  @override
  Future<void> setTicketStatus(String id, TicketStatus status) =>
      _api.post<Map<String, dynamic>>(
        '/v1/review/support/tickets/$id/status',
        body: {'status': status.wire},
      );
}
