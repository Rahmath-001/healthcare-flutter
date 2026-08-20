import 'package:firebase_auth/firebase_auth.dart';

/// Thin view over a Firebase [User] for the UI layer.
class AppUser {
  final String uid;
  final String? name;
  final String? phone;
  final String? photoUrl;

  /// 'google' | 'phone' | 'unknown'
  final String provider;

  const AppUser({
    required this.uid,
    this.name,
    this.phone,
    this.photoUrl,
    required this.provider,
  });

  factory AppUser.fromFirebase(User u) {
    final pid =
        u.providerData.isNotEmpty ? u.providerData.first.providerId : '';
    final provider = pid.contains('google')
        ? 'google'
        : (pid.contains('phone') || u.phoneNumber != null)
            ? 'phone'
            : 'unknown';
    return AppUser(
      uid: u.uid,
      name: u.displayName,
      phone: u.phoneNumber,
      photoUrl: u.photoURL,
      provider: provider,
    );
  }

  String get greetingName =>
      (name != null && name!.trim().isNotEmpty) ? name! : (phone ?? 'there');
}
