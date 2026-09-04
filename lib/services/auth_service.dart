import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../models/app_user.dart';

/// Firebase-facing identity operations: Google, Apple, email/password, and India phone OTP.
///
/// This class proves *who* the user is and nothing more. Authorization — role,
/// provider status, scopes — is owned by the MiDoctor API and lives on the
/// session, not here. Deliberately not a ChangeNotifier: auth state is exposed
/// as a stream via `firebaseUserProvider`.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? google,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _google = google ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  AppUser? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : AppUser.fromFirebase(u);
  }

  bool get isSignedIn => _auth.currentUser != null;

  /// The Firebase ID token, exchanged by the API for a MiDoctor session.
  ///
  /// [forceRefresh] re-mints it; used after a role change so the exchange sees
  /// current identity claims.
  Future<String?> idToken({bool forceRefresh = false}) =>
      _auth.currentUser?.getIdToken(forceRefresh) ?? Future.value();

  // --- Google OAuth ---------------------------------------------------------

  Future<void> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) return; // user cancelled
    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  /// Used for provisioned organisation accounts. Registration never exposes
  /// this path, so a hospital cannot self-create a privileged account.
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // --- Apple ----------------------------------------------------------------

  /// Sign in with Apple.
  ///
  /// Required by App Store review whenever a third-party login is offered, and
  /// Google sign-in is offered here — so shipping iOS without this is an
  /// automatic rejection.
  ///
  /// The nonce is sent to Apple hashed and to Firebase raw; Firebase hashes it
  /// again and compares, which is what prevents a stolen credential from being
  /// replayed.
  Future<void> signInWithApple() async {
    final rawNonce = _generateNonce();

    final AuthorizationCredentialAppleID appleCredential;
    try {
      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      // Dismissing the sheet is a decision, not a failure. Google's flow
      // returns null on cancel; this makes Apple behave the same way so the
      // caller never has to show an error for "changed my mind".
      if (e.code == AuthorizationErrorCode.canceled) return;
      rethrow;
    }

    // Apple hands out the authorization code exactly once, here. Deleting an
    // account later must revoke it (App Store Review 5.1.1(v)), and there is no
    // way to ask for it again at that point — so it is captured now.
    _appleAuthorizationCode = appleCredential.authorizationCode;

    final credential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );
    final result = await _auth.signInWithCredential(credential);

    // Apple returns the display name only on the very first authorization, so
    // it has to be captured now or it is gone for good.
    final given = appleCredential.givenName;
    final family = appleCredential.familyName;
    if ((result.user?.displayName ?? '').isEmpty &&
        (given != null || family != null)) {
      final name = [given, family].whereType<String>().join(' ').trim();
      if (name.isNotEmpty) {
        await result.user?.updateDisplayName(name);
        await result.user?.reload();
      }
    }
  }

  /// Whether Sign in with Apple can be offered on this device.
  static Future<bool> get isAppleSignInAvailable =>
      SignInWithApple.isAvailable();

  /// Apple's single-use authorization code from the current sign-in, if the
  /// user signed in with Apple during this app run.
  String? _appleAuthorizationCode;

  /// Revokes the Apple token, severing the link between this app and the user's
  /// Apple ID.
  ///
  /// Apple requires this whenever an account is deleted, not merely that the
  /// account disappears from our side; an app that leaves the connection alive
  /// fails review. Best-effort by design: a failure here must never block the
  /// deletion itself, or a user who wants to leave cannot.
  ///
  /// Only possible when the user signed in with Apple *in this session* — the
  /// code is not persisted. A user who deletes their account after a cold start
  /// needs the server to revoke instead, using a refresh token stored at
  /// sign-up time.
  Future<void> revokeAppleToken() async {
    final code = _appleAuthorizationCode;
    if (code == null) return;
    try {
      await _auth.revokeTokenWithAuthorizationCode(code);
      _appleAuthorizationCode = null;
    } on FirebaseAuthException catch (e) {
      // Also thrown on non-Apple platforms, where there is nothing to revoke.
      if (kDebugMode) debugPrint('Apple token revocation failed: ${e.code}');
    }
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  // --- Phone OTP ------------------------------------------------------------

  /// Pending verificationId between code-sent and code-verify.
  String? _verificationId;
  int? _resendToken;

  /// Kicks off OTP. Carrier/VoIP gate must have already passed before calling.
  /// [onCodeSent] fires when the SMS is dispatched. [onAutoVerified] fires when
  /// Android auto-retrieves the code (sign-in already done in that case).
  /// [onError] surfaces verification failures.
  Future<void> startPhoneAuth({
    required String e164,
    required VoidCallback onCodeSent,
    required void Function(String message) onError,
    VoidCallback? onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: e164,
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential cred) async {
        await _auth.signInWithCredential(cred);
        onAutoVerified?.call();
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(e.message ?? 'Verification failed');
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        onCodeSent();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  /// Verifies the 6-digit [smsCode]. Optionally sets display name on success
  /// (used by the signup flow).
  Future<void> verifyOtp(String smsCode, {String? displayName}) async {
    final id = _verificationId;
    if (id == null) {
      throw FirebaseAuthException(
        code: 'no-verification-id',
        message: 'Request a code first.',
      );
    }
    final cred = PhoneAuthProvider.credential(
      verificationId: id,
      smsCode: smsCode,
    );
    final result = await _auth.signInWithCredential(cred);
    if (displayName != null && displayName.trim().isNotEmpty) {
      await result.user?.updateDisplayName(displayName.trim());
      await result.user?.reload();
    }
  }

  // --- Sign out -------------------------------------------------------------

  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}
