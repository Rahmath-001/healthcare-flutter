import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

/// Riverpod bindings for the Firebase-facing services.
///
/// Riverpod 3 dropped ChangeNotifierProvider, and these are better expressed as
/// streams anyway: auth state and connectivity are both event sources, not
/// mutable objects the UI pokes at.

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(auth: ref.watch(firebaseAuthProvider)),
);

/// The raw Firebase identity. Proves *who* the user is.
///
/// Authorization — role, provider status, scopes — comes from the MiDoctor
/// session instead; see `currentSessionProvider`.
final firebaseUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

/// Whether to offer Sign in with Apple on this device.
///
/// Two conditions, both necessary. The platform check keeps the button off
/// Android and web: `sign_in_with_apple` can run there via a Service ID web
/// flow, but that needs Apple server-side credentials this project has not set
/// up, so offering it would produce a button that only ever fails. The
/// `isAvailable` check then excludes iOS below 13, where the framework does not
/// exist at all.
///
/// Apple platforms must show it — App Store Review 4.8 requires Sign in with
/// Apple wherever another third-party login is offered, and Google is offered.
final appleSignInAvailableProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb) return false;
  final isApplePlatform = defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  if (!isApplePlatform) return false;
  return AuthService.isAppleSignInAvailable;
});

final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

/// True when the device has any network interface up.
///
/// Note this reports reachability of the *interface*, not of our API: an Indian
/// mobile connection frequently reports "connected" while carrying no usable
/// traffic. It drives the offline banner only; request failures are handled by
/// the API client.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = ref.watch(connectivityProvider);
  bool online(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);

  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});
