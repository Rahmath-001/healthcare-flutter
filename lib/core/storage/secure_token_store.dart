import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence for the MiDoctor refresh token.
///
/// Deliberate split, per the security design:
///  * the **access token** is held in memory only and is never written to disk;
///  * the **refresh token** is written here, backed by the iOS Keychain and the
///    Android KeyStore (AES-GCM under an RSA-OAEP-wrapped key).
///
/// The spec's "HttpOnly cookie" is a web construct with no mobile equivalent;
/// Keychain/Keystore is the mobile-correct and strictly stronger option.
///
/// Nothing clinical is ever stored here. This is credentials only.
///
/// ## Web is different, on purpose
///
/// `flutter_secure_storage` on web is `localStorage` wearing a keychain's name.
/// It is readable by any script running on the origin, so a single XSS — an
/// injected analytics tag, a compromised dependency — exfiltrates a long-lived
/// refresh token, and the rotation/reuse-detection design on the server assumes
/// that token is *not* script-readable.
///
/// So on web the refresh token and session id are held **in memory only** and
/// never touch `localStorage`. The cost is real and is accepted deliberately:
/// reloading the tab signs you out. That is the correct trade for a credential
/// that unlocks health records, and it is the more appropriate behaviour for
/// the operator console in particular, where the same credential can suspend an
/// account or open a doctor's identity documents.
///
/// This is a mitigation, not the fix. The fix is a same-site `HttpOnly` refresh
/// cookie issued by the API, which is a server-side change — see
/// [docs/SECURITY_AUDIT.md](../../../docs/SECURITY_AUDIT.md).
class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // flutter_secure_storage 11 backs Android with AES-GCM data
              // encryption under an RSA-OAEP-wrapped KeyStore key.
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                // Readable only after first unlock, and never restored onto a
                // different device from a backup.
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Web-only holding area for the two values that must not be persisted.
  ///
  /// An instance field rather than a static, so a second store (tests, a second
  /// `ProviderScope`) does not inherit the first one's credentials.
  final Map<String, String> _ephemeral = <String, String>{};

  static const _kRefreshToken = 'midoctor.refresh_token';
  static const _kSessionId = 'midoctor.session_id';
  static const _kDeviceId = 'midoctor.device_id';

  /// True for the values that are bearer credentials.
  ///
  /// The device id is deliberately excluded: it is an opaque per-install
  /// identifier, not a secret, and keeping it persistent on web is what stops
  /// every page load registering as a new device and flooding the device list
  /// the user is supposed to be able to review.
  static bool _isCredential(String key) =>
      key == _kRefreshToken || key == _kSessionId;

  Future<String?> _read(String key) async {
    if (kIsWeb && _isCredential(key)) return _ephemeral[key];
    return _storage.read(key: key);
  }

  Future<void> _write(String key, String value) async {
    if (kIsWeb && _isCredential(key)) {
      _ephemeral[key] = value;
      return;
    }
    await _storage.write(key: key, value: value);
  }

  Future<void> _delete(String key) async {
    if (kIsWeb && _isCredential(key)) {
      _ephemeral.remove(key);
      return;
    }
    await _storage.delete(key: key);
  }

  Future<String?> readRefreshToken() => _read(_kRefreshToken);

  Future<void> writeRefreshToken(String token) => _write(_kRefreshToken, token);

  Future<String?> readSessionId() => _read(_kSessionId);

  Future<void> writeSessionId(String sid) => _write(_kSessionId, sid);

  /// Stable per-install identifier, used for the device list and per-device
  /// revocation. Not a hardware id: it dies with the app install, by design.
  Future<String?> readDeviceId() => _read(_kDeviceId);

  Future<void> writeDeviceId(String id) => _write(_kDeviceId, id);

  /// Wipes credentials on sign-out or on refresh-token reuse detection.
  /// [readDeviceId] is preserved so the same install keeps its identity.
  Future<void> clearSession() async {
    await _delete(_kRefreshToken);
    await _delete(_kSessionId);

    // Belt and braces for a build that ran an older version of this class and
    // left a token in localStorage: on web, also clear the persisted copies so
    // an upgrade does not leave the very credential this class exists to keep
    // out of storage sitting there indefinitely.
    if (kIsWeb) {
      await _storage.delete(key: _kRefreshToken);
      await _storage.delete(key: _kSessionId);
    }
  }
}
