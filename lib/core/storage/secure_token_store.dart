import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence for the MiDoctor refresh token.
///
/// Deliberate split, per the security design:
///  * the **access token** is held in memory only and is never written to disk;
///  * the **refresh token** is written here, backed by the iOS Keychain and
///    Android EncryptedSharedPreferences.
///
/// The spec's "HttpOnly cookie" is a web construct with no mobile equivalent;
/// Keychain/Keystore is the mobile-correct and strictly stronger option.
///
/// Nothing clinical is ever stored here. This is credentials only.
class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // flutter_secure_storage 11 always backs Android with
              // EncryptedSharedPreferences (AES-GCM via the Keystore); the old
              // opt-in flag no longer exists.
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                // Readable only after first unlock, and never restored onto a
                // different device from a backup.
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _kRefreshToken = 'midoctor.refresh_token';
  static const _kSessionId = 'midoctor.session_id';
  static const _kDeviceId = 'midoctor.device_id';

  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _kRefreshToken, value: token);

  Future<String?> readSessionId() => _storage.read(key: _kSessionId);

  Future<void> writeSessionId(String sid) =>
      _storage.write(key: _kSessionId, value: sid);

  /// Stable per-install identifier, used for the device list and per-device
  /// revocation. Not a hardware id: it dies with the app install, by design.
  Future<String?> readDeviceId() => _storage.read(key: _kDeviceId);

  Future<void> writeDeviceId(String id) =>
      _storage.write(key: _kDeviceId, value: id);

  /// Wipes credentials on sign-out or on refresh-token reuse detection.
  /// [readDeviceId] is preserved so the same install keeps its identity.
  Future<void> clearSession() async {
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kSessionId);
  }
}
