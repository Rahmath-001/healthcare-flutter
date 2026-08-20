import '../../../core/error/failure.dart';
import '../../../core/fixtures/fixture_backend.dart';
import '../domain/consent.dart';

/// Consent grants, requests and the access log.
///
/// Every method here enforces one rule: access to a medical record is always
/// time-boxed, always attributable, and always revocable. There is no call that
/// grants open-ended access, because no such grant may exist.
abstract class ConsentRepository {
  Future<List<RecordAccessGrant>> grants();
  Future<List<RecordAccessRequest>> pendingRequests();
  Future<List<RecordAccessEvent>> accessLog();

  Future<RecordAccessGrant> grant({
    required String providerId,
    required String providerName,
    required String providerSpecialty,
    required ConsentScopeKind scopeKind,
    required ConsentPurpose purpose,
    required Duration duration,
    List<String> recordIds,
    List<String> recordTypeLabels,
    String? appointmentReference,
  });

  Future<void> revoke(String grantId);

  Future<RecordAccessGrant> approveRequest(
    String requestId, {
    required Duration duration,
    required ConsentScopeKind scopeKind,
    List<String> recordIds,
  });

  Future<void> denyRequest(String requestId);
}

class FixtureConsentRepository implements ConsentRepository {
  FixtureConsentRepository({
    this.latency = const Duration(milliseconds: 320),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  /// Nothing may be granted for longer than this, ever.
  ///
  /// Enforced here as well as in the UI, because a grant with no end is
  /// indistinguishable from having handed over a copy.
  static const maxDuration = Duration(days: 180);

  @override
  Future<List<RecordAccessGrant>> grants() async {
    await Future<void>.delayed(latency);
    return _backend.grants();
  }

  @override
  Future<List<RecordAccessRequest>> pendingRequests() async {
    await Future<void>.delayed(latency);
    return _backend.pendingRequests();
  }

  @override
  Future<List<RecordAccessEvent>> accessLog() async {
    await Future<void>.delayed(latency);
    return _backend.accessLog();
  }

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
    await Future<void>.delayed(latency);

    if (duration <= Duration.zero) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Access must have an end date.',
        code: 'DURATION_REQUIRED',
      );
    }
    if (duration > maxDuration) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Access cannot last longer than 180 days.',
        code: 'GRANT_TOO_LONG',
      );
    }
    if (scopeKind == ConsentScopeKind.specificRecords && recordIds.isEmpty) {
      throw const Failure(
        kind: FailureKind.validation,
        message: 'Choose at least one record to share.',
        code: 'NO_RECORDS_SELECTED',
      );
    }

    final now = DateTime.now();
    return _backend.addGrant(
      RecordAccessGrant(
        id: 'g-${now.millisecondsSinceEpoch}',
        providerId: providerId,
        providerName: providerName,
        providerSpecialty: providerSpecialty,
        scopeKind: scopeKind,
        purpose: purpose,
        grantedAt: now,
        expiresAt: now.add(duration),
        recordIds: recordIds,
        recordTypeLabels: recordTypeLabels,
        appointmentReference: appointmentReference,
      ),
    );
  }

  @override
  Future<void> revoke(String grantId) async {
    await Future<void>.delayed(latency);
    _backend.revokeGrant(grantId);
  }

  @override
  Future<RecordAccessGrant> approveRequest(
    String requestId, {
    required Duration duration,
    required ConsentScopeKind scopeKind,
    List<String> recordIds = const [],
  }) async {
    await Future<void>.delayed(latency);

    final request = _backend.requestById(requestId);
    if (!request.isPending) {
      throw const Failure(
        kind: FailureKind.conflict,
        message: 'That request is no longer open.',
        code: 'REQUEST_NOT_PENDING',
      );
    }

    _backend.resolveRequest(requestId, approved: true);

    // Approving a request *is* granting consent — it does not merely mark the
    // request answered, or the doctor would still have no access.
    return grant(
      providerId: request.providerId,
      providerName: request.providerName,
      providerSpecialty: request.providerSpecialty,
      scopeKind: scopeKind,
      purpose: request.purpose,
      duration: duration,
      recordIds: recordIds,
      appointmentReference: request.appointmentReference,
    );
  }

  @override
  Future<void> denyRequest(String requestId) async {
    await Future<void>.delayed(latency);
    _backend.resolveRequest(requestId, approved: false);
  }
}
