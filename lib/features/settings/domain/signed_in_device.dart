import 'package:meta/meta.dart';

/// One place this account is currently signed in.
///
/// ## What this deliberately does not carry
///
/// No IP address, no city, no hardware identifier. A "signed in from Mumbai,
/// 49.36.x.x" line reads as reassuring security detail and is really a
/// location history of the account holder, retained indefinitely, shown to
/// whoever is holding an unlocked phone — including the person a patient might
/// be hiding a consultation from. The DPDP Act's minimisation duty points the
/// same way: the question this screen answers is "is there a session here I do
/// not recognise", and platform plus last-seen answers it.
///
/// The device id behind a session is a random per-install string, never a
/// hardware id, for the same reason.
@immutable
class SignedInDevice {
  const SignedInDevice({
    required this.id,
    required this.platform,
    required this.appVersion,
    required this.createdAt,
    required this.lastSeenAt,
    required this.isCurrent,
  });

  /// The session id. Revoking addresses this.
  final String id;

  /// `android`, `ios` or `web`, as reported at sign-in.
  final String platform;

  final String appVersion;
  final DateTime createdAt;
  final DateTime lastSeenAt;

  /// Whether this is the session doing the asking.
  ///
  /// Decided by the server, which knows which session presented the token,
  /// rather than by the client comparing ids — a client that got this wrong
  /// would offer "sign out everywhere else" and sign the user out of the
  /// device in their hand.
  final bool isCurrent;

  String get platformLabel => switch (platform.toLowerCase()) {
        'android' => 'Android',
        'ios' => 'iPhone or iPad',
        'web' => 'Web browser',
        _ => 'Unknown device',
      };

  /// Sessions untouched for a fortnight, which are worth a second look.
  ///
  /// Not a security verdict — an old session is usually a spare tablet. It is
  /// a nudge towards the ones a person is least likely to remember creating.
  bool staleAt(DateTime now) => now.difference(lastSeenAt).inDays >= 14;

  factory SignedInDevice.fromJson(Map<String, dynamic> json) => SignedInDevice(
        id: json['id'] as String,
        platform: (json['platform'] as String?) ?? '',
        appVersion: (json['appVersion'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        lastSeenAt: DateTime.parse(json['lastSeenAt'] as String).toLocal(),
        isCurrent: (json['isCurrent'] as bool?) ?? false,
      );
}
