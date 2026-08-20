import 'dart:convert';

import '../../../core/fixtures/fixture_backend.dart';
import '../../../core/network/api_client.dart';
import '../domain/account_deletion.dart';
import '../domain/patient_profile.dart';

/// The account itself: the profile on it, and the two DPDP rights that act on
/// the whole of it.
///
/// Kept separate from `SessionRepository`, which is about proving identity and
/// holding tokens. These are operations on the person's data, not on their
/// session.
abstract class AccountRepository {
  /// The caller's own profile, including the clinical fields the onboarding
  /// flow collects.
  Future<PatientProfile> profile();

  Future<PatientProfile> updateProfile(PatientProfileDraft draft);

  /// DPDP s.11 — everything held about the caller, as portable JSON.
  Future<String> exportData();

  /// DPDP s.12 / App Store 5.1.1(v) — erasure.
  ///
  /// Returns when the request has been recorded and the caller has been signed
  /// out everywhere. The clinical tail is retained for the statutory period
  /// carried on the result.
  Future<AccountDeletion> requestDeletion();
}

class ApiAccountRepository implements AccountRepository {
  ApiAccountRepository(this._api);

  final ApiClient _api;

  @override
  Future<PatientProfile> profile() async {
    final json = await _api.get<Map<String, dynamic>>('/v1/me');
    return PatientProfile.fromJson(json);
  }

  @override
  Future<PatientProfile> updateProfile(PatientProfileDraft draft) async {
    await _api.put<Map<String, dynamic>>('/v1/me', body: draft.toJson());
    return profile();
  }

  @override
  Future<String> exportData() async {
    final json = await _api.get<Map<String, dynamic>>('/v1/me/export');
    // Pretty-printed because the file is for a person to read, not a parser.
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  @override
  Future<AccountDeletion> requestDeletion() async {
    final json = await _api.delete<Map<String, dynamic>>('/v1/me');
    return AccountDeletion.fromJson(json);
  }
}

/// In-memory stand-in that mirrors the API's semantics closely enough to build
/// and test the screens against.

class FixtureAccountRepository implements AccountRepository {
  FixtureAccountRepository({
    this.latency = const Duration(milliseconds: 400),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<PatientProfile> profile() async {
    await Future<void>.delayed(latency);
    return _backend.profile();
  }

  @override
  Future<PatientProfile> updateProfile(PatientProfileDraft draft) async {
    await Future<void>.delayed(latency);
    return _backend.updateProfile(draft);
  }

  /// Assembled from the same store every screen reads, so an export reflects
  /// what the user can actually see rather than a separately-maintained
  /// approximation of it.
  @override
  Future<String> exportData() async {
    await Future<void>.delayed(latency);

    final profile = _backend.profile();
    return const JsonEncoder.withIndent('  ').convert({
      'generatedAt': DateTime.now().toIso8601String(),
      'account': {
        'userId': profile.userId,
        'displayName': profile.displayName,
        'email': profile.email,
        'phone': profile.phone,
        'bloodGroup': profile.bloodGroup?.label,
        'allergies': profile.allergies,
        'chronicConditions': profile.chronicConditions,
      },
      'appointments': [
        for (final a in _backend.appointments())
          {
            'reference': a.referenceCode,
            'doctor': a.doctor.name,
            'start': a.start.toIso8601String(),
            'status': a.status.name,
          },
      ],
      'records': [
        for (final r in _backend.records())
          {
            'title': r.title,
            'type': r.type.label,
            'recordedAt': r.recordedAt.toIso8601String(),
          },
      ],
      'consentGrants': [
        for (final g in _backend.grants())
          {
            'provider': g.providerName,
            'grantedAt': g.grantedAt.toIso8601String(),
            'expiresAt': g.expiresAt.toIso8601String(),
            'revoked': g.revokedAt != null,
          },
      ],
      'recordAccessLog': [
        for (final e in _backend.accessLog())
          {
            'actor': e.actorName,
            'record': e.recordTitle,
            'action': e.action.name,
            'at': e.at.toIso8601String(),
          },
      ],
    });
  }

  @override
  Future<AccountDeletion> requestDeletion() async {
    await Future<void>.delayed(latency);
    return AccountDeletion(
      clinicalRetentionUntil: DateTime.now().add(const Duration(days: 3 * 365)),
    );
  }
}
