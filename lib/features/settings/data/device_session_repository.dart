import '../../../core/fixtures/fixture_backend.dart';
import '../../../core/network/api_client.dart';
import '../domain/signed_in_device.dart';

/// Where this account is signed in, and how to end one of those sessions.
///
/// The control this exists for: a patient hands their phone to a relative in a
/// clinic waiting room, or signs in on a shared machine and forgets. Without
/// this, the only remedy is changing a password — and there is no password
/// here, because identity is Google, Apple or an OTP.
abstract class DeviceSessionRepository {
  /// Live sessions, current one first.
  Future<List<SignedInDevice>> list();

  /// Ends one session. Passing the current one signs this device out.
  Future<void> revoke(String sessionId);

  /// Ends every session except the one asking.
  ///
  /// The button people actually want: "something is wrong, get everyone else
  /// out" without having to work out which row is their own phone.
  Future<int> revokeOthers();
}

class FixtureDeviceSessionRepository implements DeviceSessionRepository {
  FixtureDeviceSessionRepository({
    this.latency = const Duration(milliseconds: 220),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<List<SignedInDevice>> list() async {
    await Future<void>.delayed(latency);
    return _backend.signedInDevices();
  }

  @override
  Future<void> revoke(String sessionId) async {
    await Future<void>.delayed(latency);
    _backend.revokeDeviceSession(sessionId);
  }

  @override
  Future<int> revokeOthers() async {
    await Future<void>.delayed(latency);
    return _backend.revokeOtherDeviceSessions();
  }
}

class ApiDeviceSessionRepository implements DeviceSessionRepository {
  ApiDeviceSessionRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<SignedInDevice>> list() async {
    final json = await _api.get<List<dynamic>>('/v1/auth/sessions');
    return json
        .map((e) => SignedInDevice.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> revoke(String sessionId) =>
      _api.delete<Map<String, dynamic>>('/v1/auth/sessions/$sessionId');

  @override
  Future<int> revokeOthers() async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/auth/sessions/revoke-others',
    );
    return (json['revoked'] as num?)?.toInt() ?? 0;
  }
}
