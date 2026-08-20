import 'package:flutter/foundation.dart';

/// What the record access is *for*.
///
/// Purpose is recorded per grant because "who saw my data" is only meaningful
/// alongside "and why". It is also what makes an emergency access reviewable
/// after the fact.
enum ConsentPurpose {
  consultation,
  secondOpinion,
  continuityOfCare,
  emergency;

  String get label => switch (this) {
        ConsentPurpose.consultation => 'For a consultation',
        ConsentPurpose.secondOpinion => 'For a second opinion',
        ConsentPurpose.continuityOfCare => 'For ongoing care',
        ConsentPurpose.emergency => 'Emergency access',
      };

  String get wire => switch (this) {
        ConsentPurpose.consultation => 'CONSULTATION',
        ConsentPurpose.secondOpinion => 'SECOND_OPINION',
        ConsentPurpose.continuityOfCare => 'CONTINUITY_OF_CARE',
        ConsentPurpose.emergency => 'EMERGENCY',
      };

  static ConsentPurpose fromWire(String? raw) => switch (raw?.toUpperCase()) {
        'SECOND_OPINION' => ConsentPurpose.secondOpinion,
        'CONTINUITY_OF_CARE' => ConsentPurpose.continuityOfCare,
        'EMERGENCY' => ConsentPurpose.emergency,
        _ => ConsentPurpose.consultation,
      };
}

/// How much of the record set a grant covers.
enum ConsentScopeKind {
  specificRecords,
  recordTypes,
  allRecords;

  String get label => switch (this) {
        ConsentScopeKind.specificRecords => 'Selected records',
        ConsentScopeKind.recordTypes => 'Selected categories',
        ConsentScopeKind.allRecords => 'All records',
      };

  String get wire => switch (this) {
        ConsentScopeKind.specificRecords => 'SPECIFIC_RECORDS',
        ConsentScopeKind.recordTypes => 'RECORD_TYPES',
        ConsentScopeKind.allRecords => 'ALL_RECORDS',
      };

  static ConsentScopeKind fromWire(String? raw) => switch (raw?.toUpperCase()) {
        'SPECIFIC_RECORDS' => ConsentScopeKind.specificRecords,
        'RECORD_TYPES' => ConsentScopeKind.recordTypes,
        _ => ConsentScopeKind.allRecords,
      };
}

/// A time-boxed, revocable permission for one provider to read specified
/// records.
///
/// Every grant expires. There is no such thing as perpetual access: the API
/// enforces a hard 180-day ceiling, and nothing in the UI can offer more.
@immutable
class RecordAccessGrant {
  const RecordAccessGrant({
    required this.id,
    required this.providerId,
    required this.providerName,
    required this.providerSpecialty,
    required this.scopeKind,
    required this.purpose,
    required this.grantedAt,
    required this.expiresAt,
    this.recordIds = const [],
    this.recordTypeLabels = const [],
    this.revokedAt,
    this.usesCount = 0,
    this.appointmentReference,
  });

  final String id;
  final String providerId;
  final String providerName;
  final String providerSpecialty;
  final ConsentScopeKind scopeKind;
  final ConsentPurpose purpose;
  final DateTime grantedAt;
  final DateTime expiresAt;
  final List<String> recordIds;
  final List<String> recordTypeLabels;
  final DateTime? revokedAt;
  final int usesCount;
  final String? appointmentReference;

  bool get isRevoked => revokedAt != null;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isRevoked && !isExpired;

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  String get scopeLabel => switch (scopeKind) {
        ConsentScopeKind.allRecords => 'All records',
        ConsentScopeKind.recordTypes => recordTypeLabels.join(', '),
        ConsentScopeKind.specificRecords =>
          '${recordIds.length} record${recordIds.length == 1 ? '' : 's'}',
      };

  factory RecordAccessGrant.fromJson(Map<String, dynamic> json) =>
      RecordAccessGrant(
        id: json['id'] as String,
        providerId: json['providerId'] as String? ?? '',
        providerName: json['providerName'] as String? ?? '',
        providerSpecialty: json['providerSpecialty'] as String? ?? '',
        scopeKind: ConsentScopeKind.fromWire(json['scopeKind'] as String?),
        purpose: ConsentPurpose.fromWire(json['purpose'] as String?),
        grantedAt: DateTime.parse(json['grantedAt'] as String).toLocal(),
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
        recordIds: (json['recordIds'] as List<dynamic>? ?? const [])
            .map((r) => r.toString())
            .toList(),
        recordTypeLabels:
            (json['recordTypeLabels'] as List<dynamic>? ?? const [])
                .map((r) => r.toString())
                .toList(),
        revokedAt: json['revokedAt'] == null
            ? null
            : DateTime.parse(json['revokedAt'] as String).toLocal(),
        usesCount: (json['usesCount'] as num?)?.toInt() ?? 0,
        appointmentReference: json['appointmentReference'] as String?,
      );

  RecordAccessGrant copyWith({
    DateTime? revokedAt,
    int? usesCount,
    List<String>? recordIds,
  }) =>
      RecordAccessGrant(
        id: id,
        providerId: providerId,
        providerName: providerName,
        providerSpecialty: providerSpecialty,
        scopeKind: scopeKind,
        purpose: purpose,
        grantedAt: grantedAt,
        expiresAt: expiresAt,
        recordIds: recordIds ?? this.recordIds,
        recordTypeLabels: recordTypeLabels,
        revokedAt: revokedAt ?? this.revokedAt,
        usesCount: usesCount ?? this.usesCount,
        appointmentReference: appointmentReference,
      );
}

/// A provider asking for access. The patient answers; silence is a denial.
///
/// A provider cannot request access to someone they have no appointment
/// relationship with, and a request auto-expires after 72 hours — together
/// these stop the request channel becoming a fishing tool.
enum AccessRequestStatus { pending, approved, denied, expired, withdrawn }

@immutable
class RecordAccessRequest {
  const RecordAccessRequest({
    required this.id,
    required this.providerId,
    required this.providerName,
    required this.providerSpecialty,
    required this.purpose,
    required this.requestedAt,
    required this.expiresAt,
    required this.status,
    this.message,
    this.appointmentReference,
  });

  final String id;
  final String providerId;
  final String providerName;
  final String providerSpecialty;
  final ConsentPurpose purpose;
  final DateTime requestedAt;
  final DateTime expiresAt;
  final AccessRequestStatus status;
  final String? message;
  final String? appointmentReference;

  RecordAccessRequest copyWith({AccessRequestStatus? status}) =>
      RecordAccessRequest(
        id: id,
        providerId: providerId,
        providerName: providerName,
        providerSpecialty: providerSpecialty,
        purpose: purpose,
        requestedAt: requestedAt,
        expiresAt: expiresAt,
        status: status ?? this.status,
        message: message,
        appointmentReference: appointmentReference,
      );

  bool get isPending =>
      status == AccessRequestStatus.pending &&
      DateTime.now().isBefore(expiresAt);

  factory RecordAccessRequest.fromJson(Map<String, dynamic> json) =>
      RecordAccessRequest(
        id: json['id'] as String,
        providerId: json['providerId'] as String? ?? '',
        providerName: json['providerName'] as String? ?? '',
        providerSpecialty: json['providerSpecialty'] as String? ?? '',
        purpose: ConsentPurpose.fromWire(json['purpose'] as String?),
        requestedAt: DateTime.parse(json['requestedAt'] as String).toLocal(),
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
        status: switch ((json['status'] as String?)?.toUpperCase()) {
          'APPROVED' => AccessRequestStatus.approved,
          'DENIED' => AccessRequestStatus.denied,
          'EXPIRED' => AccessRequestStatus.expired,
          'WITHDRAWN' => AccessRequestStatus.withdrawn,
          _ => AccessRequestStatus.pending,
        },
        message: json['message'] as String?,
        appointmentReference: json['appointmentReference'] as String?,
      );
}

/// One touch of one record, including refusals.
///
/// Denials are logged as deliberately as reads: a burst of denied attempts is
/// the clearest fraud signal the system produces.
enum AccessAction { viewMetadata, view, download, denied }

@immutable
class RecordAccessEvent {
  const RecordAccessEvent({
    required this.id,
    required this.actorName,
    required this.recordTitle,
    required this.action,
    required this.at,
    this.purpose,
  });

  final String id;
  final String actorName;
  final String recordTitle;
  final AccessAction action;
  final DateTime at;
  final ConsentPurpose? purpose;

  String get actionLabel => switch (action) {
        AccessAction.viewMetadata => 'saw the file listing for',
        AccessAction.view => 'viewed',
        AccessAction.download => 'downloaded',
        AccessAction.denied => 'was denied access to',
      };

  factory RecordAccessEvent.fromJson(Map<String, dynamic> json) =>
      RecordAccessEvent(
        id: json['id'] as String,
        actorName: json['actorName'] as String? ?? '',
        recordTitle: json['recordTitle'] as String? ?? '',
        action: switch ((json['action'] as String?)?.toUpperCase()) {
          'VIEW' => AccessAction.view,
          'DOWNLOAD' => AccessAction.download,
          'DENIED' => AccessAction.denied,
          _ => AccessAction.viewMetadata,
        },
        at: DateTime.parse(json['at'] as String).toLocal(),
        purpose: json['purpose'] == null
            ? null
            : ConsentPurpose.fromWire(json['purpose'] as String?),
      );
}

/// Durations the UI is allowed to offer for a patient-initiated grant.
///
/// Kept well under the server's 180-day ceiling: the shortest workable window
/// should be the easiest to pick.
enum ConsentDuration {
  oneDay(Duration(days: 1), '24 hours'),
  oneWeek(Duration(days: 7), '7 days'),
  oneMonth(Duration(days: 30), '30 days'),
  threeMonths(Duration(days: 90), '90 days');

  const ConsentDuration(this.duration, this.label);
  final Duration duration;
  final String label;
}
