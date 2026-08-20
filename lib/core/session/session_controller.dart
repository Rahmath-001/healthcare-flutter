import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error/failure.dart';
import '../../features/auth/data/session_repository.dart';
import '../../features/auth/presentation/role_selection_screen.dart';
import '../observability/crash_reporting.dart';
import '../providers.dart';
import '../service_providers.dart';
import '../storage/secure_token_store.dart';
import 'session.dart';
import 'user_role.dart';

/// Owns the MiDoctor session: restore on launch, exchange after Firebase
/// sign-in, refresh, and sign-out.
///
/// The access token lives here in memory and is never written to disk. Only the
/// refresh token reaches [SecureTokenStore].
class SessionController extends AsyncNotifier<Session?> {
  SessionRepository get _repository => ref.read(sessionRepositoryProvider);
  SecureTokenStore get _store => ref.read(secureTokenStoreProvider);

  /// Read synchronously by the Dio interceptor on every request, so it must not
  /// depend on the AsyncValue being in a data state.
  String? _accessToken;
  String? get accessToken => _accessToken;

  @override
  Future<Session?> build() async => _restore();

  /// Attempts to resume a session from the stored refresh token. A failure here
  /// is normal (first launch, expired or revoked token) and yields a signed-out
  /// state rather than an error.
  Future<Session?> _restore() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null) return null;

    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      final result = await _repository.refresh(
        refreshToken: refreshToken,
        deviceId: deviceId,
      );
      await _store.writeRefreshToken(result.refreshToken);
      _accessToken = result.session.accessToken;
      unawaited(CrashReporting.setUser(result.session.userId));
      return result.session;
    } catch (e) {
      // Includes refresh-token reuse detection, where the server has revoked
      // the whole session family. Clearing local state is the correct response.
      if (kDebugMode) debugPrint('Session restore failed: $e');
      await _clear();
      return null;
    }
  }

  /// Completes sign-in after Firebase has authenticated the user.
  ///
  /// Firebase proves *who*; this turns that into a MiDoctor session, which is
  /// what proves *what they may do*. Every sign-in path — Google, Apple, phone
  /// OTP, and the operator console — ends here, because a Firebase user with no
  /// MiDoctor session can authenticate and then do nothing at all.
  Future<void> completeFirebaseSignIn() async {
    final idToken = await ref.read(authServiceProvider).idToken();
    if (idToken == null) {
      throw const Failure(
        kind: FailureKind.unauthenticated,
        message: 'Sign-in did not complete. Please try again.',
        code: 'NO_FIREBASE_TOKEN',
      );
    }
    await exchangeFirebaseToken(idToken);

    // AsyncValue.guard swallows the throw into an error state, so a caller that
    // needs to react to failure has to be told explicitly.
    final current = state;
    if (current.hasError) {
      Error.throwWithStackTrace(current.error!, current.stackTrace!);
    }
  }

  /// Signs in against the fixture backend, without Firebase.
  ///
  /// Sample data has no identity provider behind it, so every sign-in path in
  /// fixture mode would otherwise die at `Firebase.initializeApp` or at a
  /// Google consent sheet that cannot return. That made the mock data
  /// unreachable: the app opened on a login screen it could not get past.
  ///
  /// Only ever reached when `USE_FIXTURES` is true — the token is a placeholder
  /// that `FixtureSessionRepository` ignores, and `ApiSessionRepository` would
  /// rightly be refused by the server.
  Future<void> signInWithSampleData({
    UserRole requestedRole = UserRole.patient,
  }) async {
    state = const AsyncValue<Session?>.loading();
    state = await AsyncValue.guard(() async {
      final result = await _repository.exchange(
        firebaseIdToken: 'fixture',
        deviceId: 'fixture-device',
        platform: 'fixture',
        appVersion: ref.read(appVersionProvider),
        requestedRole: requestedRole,
      );
      _accessToken = result.session.accessToken;
      return result.session;
    });
  }

  /// Called after Firebase sign-in succeeds. Exchanges the Firebase ID token
  /// for a MiDoctor session.
  Future<void> exchangeFirebaseToken(String firebaseIdToken) async {
    state = const AsyncValue<Session?>.loading();
    state = await AsyncValue.guard(() async {
      final deviceId = await ref.read(deviceIdProvider.future);
      final result = await _repository.exchange(
        firebaseIdToken: firebaseIdToken,
        deviceId: deviceId,
        platform: defaultTargetPlatform.name,
        appVersion: ref.read(appVersionProvider),
        requestedRole: ref.read(requestedRoleProvider),
      );
      await _store.writeRefreshToken(result.refreshToken);
      _accessToken = result.session.accessToken;
      unawaited(CrashReporting.setUser(result.session.userId));
      return result.session;
    });
  }

  /// Invoked by the auth interceptor on 401/TOKEN_STALE. Throws when the
  /// session cannot be renewed, which the interceptor turns into a sign-out.
  Future<void> refreshAccessToken() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null) {
      await signOutLocally();
      throw StateError('No refresh token available');
    }

    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      final result = await _repository.refresh(
        refreshToken: refreshToken,
        deviceId: deviceId,
      );
      await _store.writeRefreshToken(result.refreshToken);
      _accessToken = result.session.accessToken;
      unawaited(CrashReporting.setUser(result.session.userId));
      state = AsyncValue<Session?>.data(result.session);
    } catch (_) {
      await signOutLocally();
      rethrow;
    }
  }

  /// Signs out of both MiDoctor and Firebase.
  ///
  /// Order matters: revoke the server session first (which needs a valid access
  /// token), then drop the Firebase identity, then clear local credentials.
  /// Every step is best-effort — a network failure must never strand a user in
  /// a signed-in UI they cannot leave.
  Future<void> signOut() async {
    try {
      await _repository.logout();
    } catch (_) {}
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {}
    await signOutLocally();
  }

  Future<void> signOutLocally() async {
    await _clear();
    state = const AsyncValue<Session?>.data(null);
  }

  Future<void> _clear() async {
    _accessToken = null;
    // Detaches the crash reporter from the signed-out user, so later reports
    // are not attributed to someone who is no longer using the device.
    unawaited(CrashReporting.setUser(null));
    await _store.clearSession();
  }
}
