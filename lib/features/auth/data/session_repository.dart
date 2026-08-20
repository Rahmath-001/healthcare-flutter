import '../../../core/network/api_client.dart';
import '../../../core/session/session.dart';
import '../../../core/session/user_role.dart';

/// Exchanges Firebase identity for a MiDoctor session, and manages that
/// session's lifetime.
abstract class SessionRepository {
  /// `POST /v1/auth/session` — verifies the Firebase ID token server-side and
  /// mints a MiDoctor access + refresh token pair.
  ///
  /// Returns the session and the refresh token, which the caller persists to
  /// secure storage. The refresh token is returned exactly once.
  /// [requestedRole] is what the user asked to register as (FR-AUTH-002:
  /// Patient or Provider only). The server decides the actual role — this is a
  /// request, never an assertion, or anyone could claim staff privileges.
  Future<({Session session, String refreshToken})> exchange({
    required String firebaseIdToken,
    required String deviceId,
    required String platform,
    required String appVersion,
    UserRole requestedRole,
  });

  /// `POST /v1/auth/refresh` — rotates the refresh token and issues a new
  /// access token. The old refresh token is invalid afterwards; presenting it
  /// again is treated by the server as theft.
  Future<({Session session, String refreshToken})> refresh({
    required String refreshToken,
    required String deviceId,
  });

  /// `POST /v1/auth/logout` — revokes this session server-side. Best-effort:
  /// local credentials are cleared regardless of the outcome.
  Future<void> logout();
}

class ApiSessionRepository implements SessionRepository {
  ApiSessionRepository(this._api);

  final ApiClient _api;

  @override
  Future<({Session session, String refreshToken})> exchange({
    required String firebaseIdToken,
    required String deviceId,
    required String platform,
    required String appVersion,
    UserRole requestedRole = UserRole.patient,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/auth/session',
      // The Firebase ID token travels in the body, not the Authorization
      // header, so the auth interceptor does not mistake it for our own token.
      body: {
        'firebaseIdToken': firebaseIdToken,
        'deviceId': deviceId,
        'platform': platform,
        'appVersion': appVersion,
        'requestedRole': requestedRole.name.toUpperCase(),
      },
      skipAuth: true,
    );
    return _parse(json);
  }

  @override
  Future<({Session session, String refreshToken})> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/auth/refresh',
      body: {'refreshToken': refreshToken, 'deviceId': deviceId},
      skipAuth: true,
    );
    return _parse(json);
  }

  @override
  Future<void> logout() => _api.post<Map<String, dynamic>>('/v1/auth/logout');

  ({Session session, String refreshToken}) _parse(Map<String, dynamic> json) =>
      (
        session: Session.fromJson(json),
        refreshToken: json['refreshToken'] as String,
      );
}

/// Stands in for the API until the backend exists.
///
/// Lets the whole client re-architecture — router, shells, interceptors,
/// repositories — be built and exercised before a single endpoint is deployed.
/// Every screen is therefore refactored exactly once.
class FixtureSessionRepository implements SessionRepository {
  FixtureSessionRepository({
    this.role = UserRole.patient,
    this.providerStatus = ProviderStatus.notApplicable,
    this.latency = const Duration(milliseconds: 300),
  });

  final UserRole role;
  final ProviderStatus providerStatus;
  final Duration latency;

  @override
  Future<({Session session, String refreshToken})> exchange({
    required String firebaseIdToken,
    required String deviceId,
    required String platform,
    required String appVersion,
    UserRole requestedRole = UserRole.patient,
  }) async {
    await Future<void>.delayed(latency);
    // A staff role is provisioned, never requested: the server reads it from
    // the stored user and ignores what the client asked for. So a fixture
    // configured as staff stays staff, which is what lets the operator console
    // open on sample data.
    final isStaff = switch (role) {
      UserRole.supervisor ||
      UserRole.admin ||
      UserRole.supportL1 ||
      UserRole.supportL2 =>
        true,
      _ => false,
    };

    // A new provider starts at DRAFT, so the app routes them to verification
    // rather than into the provider shell.
    final resolved = isStaff
        ? (role: role, status: ProviderStatus.notApplicable)
        : requestedRole == UserRole.provider
            ? (role: UserRole.provider, status: ProviderStatus.draft)
            : (role: UserRole.patient, status: ProviderStatus.notApplicable);
    return (
      session: _session(role: resolved.role, providerStatus: resolved.status),
      refreshToken: 'fixture-refresh-token',
    );
  }

  @override
  Future<({Session session, String refreshToken})> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    await Future<void>.delayed(latency);
    return (session: _session(), refreshToken: 'fixture-refresh-token');
  }

  @override
  Future<void> logout() async {}

  Session _session({UserRole? role, ProviderStatus? providerStatus}) => Session(
        userId: 'fixture-user',
        sessionId: 'fixture-session',
        accessToken: 'fixture-access-token',
        accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
        role: role ?? this.role,
        accountStatus: AccountStatus.active,
        providerStatus: providerStatus ?? this.providerStatus,
        scopes: _scopesFor(role ?? this.role),
        permissionVersion: 1,
      );

  /// Mirrors the scope table in the plan, so fixture-backed screens are gated
  /// exactly as they will be against the real API.
  static Set<String> _scopesFor(UserRole role) => switch (role) {
        UserRole.patient => {
            'profile:read',
            'profile:write',
            'doctor:search',
            'appointment:create',
            'appointment:cancel',
            'records:read_own',
            'records:write_own',
            'consent:grant',
            'consent:revoke',
            'consent:view_log',
            'prescription:read_own',
            'consultation:join',
            'rating:write',
            'support:ticket_create',
          },
        UserRole.provider => {
            'profile:read',
            'profile:write_limited',
            'availability:write',
            'appointments:read_own',
            'records:read_granted',
            'records:request_access',
            'prescription:write',
            'consultation:host',
            'consultation:join',
            'ratings:read_own',
          },
        // Supervisors can work the verification queue and stop a doctor they
        // approved; role assignment stays admin-only, which is what the
        // console's Accounts section hides on.
        UserRole.supervisor => {
            'profile:read',
            'provider:review',
            'provider:approve',
            'provider:reject',
            'user:suspend',
          },
        UserRole.supportL1 => {'profile:read', 'support:ticket_read'},
        UserRole.supportL2 => {
            'profile:read',
            'support:ticket_read',
            'support:ticket_escalate',
          },
        UserRole.admin => const {'*:*'},
        _ => const {'profile:read'},
      };
}
