import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_user.dart';

/// Central auth state. Provided at the app root via ChangeNotifierProvider.
/// Exposes Google OAuth and India phone-OTP sign-in.
class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  AuthService({FirebaseAuth? auth, GoogleSignIn? google})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = google ?? GoogleSignIn() {
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  AppUser? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : AppUser.fromFirebase(u);
  }

  bool get isSignedIn => _auth.currentUser != null;

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
      notifyListeners();
    }
  }

  // --- Sign out -------------------------------------------------------------

  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}
