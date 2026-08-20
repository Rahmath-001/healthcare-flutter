import '../../../core/network/api_client.dart';
import '../domain/consent.dart';
import 'consent_repository.dart';

/// API-backed [ConsentRepository].
///
/// Consent is the one surface where a client-side implementation would be
/// actively misleading: if the app decided whether a grant were still live,
/// revocation would be a suggestion. Every method here is a request for the
/// server to decide, and the access log is written on the server's side of the
/// call so it records what actually happened rather than what we asked for.
class ApiConsentRepository implements ConsentRepository {
  ApiConsentRepository(this._api);

  final ApiClient _api;

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(path);
    return (json['items'] as List<dynamic>)
        .map((e) => parse(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<RecordAccessGrant>> grants() =>
      _list('/v1/consent/grants', RecordAccessGrant.fromJson);

  @override
  Future<List<RecordAccessRequest>> pendingRequests() =>
      _list('/v1/consent/requests', RecordAccessRequest.fromJson);

  @override
  Future<List<RecordAccessEvent>> accessLog() =>
      _list('/v1/consent/access-log', RecordAccessEvent.fromJson);

  @override
  Future<RecordAccessGrant> grant({
    required String providerId,
    required String providerName,
    required String providerSpecialty,
    required ConsentScopeKind scopeKind,
    required ConsentPurpose purpose,
    required Duration duration,
    List<String> recordIds = const [],
    List<String> recordTypeLabels = const [],
    String? appointmentReference,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/consent/grants',
      body: {
        'providerId': providerId,
        'providerName': providerName,
        'providerSpecialty': providerSpecialty,
        'scopeKind': scopeKind.wire,
        'purpose': purpose.wire,
        // Sent as days because the server's 180-day ceiling is expressed in
        // days; sending milliseconds invites rounding arguments at the boundary.
        'durationDays': duration.inDays,
        'recordIds': recordIds,
        'recordTypeLabels': recordTypeLabels,
        if (appointmentReference != null)
          'appointmentReference': appointmentReference,
      },
    );
    return RecordAccessGrant.fromJson(json);
  }

  @override
  Future<void> revoke(String grantId) async {
    await _api.post<Map<String, dynamic>>('/v1/consent/grants/$grantId/revoke');
  }

  @override
  Future<RecordAccessGrant> approveRequest(
    String requestId, {
    required Duration duration,
    required ConsentScopeKind scopeKind,
    List<String> recordIds = const [],
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/consent/requests/$requestId/approve',
      body: {
        'durationDays': duration.inDays,
        'scopeKind': scopeKind.wire,
        'recordIds': recordIds,
      },
    );
    return RecordAccessGrant.fromJson(json);
  }

  @override
  Future<void> denyRequest(String requestId) async {
    await _api.post<Map<String, dynamic>>(
      '/v1/consent/requests/$requestId/deny',
    );
  }
}
