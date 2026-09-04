import 'package:flutter/foundation.dart';

import 'user_role.dart';

/// A MiDoctor session, as returned by `POST /v1/auth/session` and
/// `POST /v1/auth/refresh`.
///
/// This is *not* the Firebase session. Firebase Auth proves who the user is;
/// this proves what they are allowed to do, and is the only thing the API
/// trusts. Authorization state (role, provider status, scopes) is owned by
/// Postgres, not by the identity provider.
@immutable
class Session {
  const Session({
    required this.userId,
    required this.sessionId,
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.role,
    required this.accountStatus,
    required this.providerStatus,
    required this.scopes,
    required this.permissionVersion,
    this.displayName,
    this.phone,
    this.email,
    this.photoUrl,
    this.hospitalId,
  });

  final String userId;

  /// The `sid` claim. Used for per-device revocation and the device list.
  final String sessionId;

  /// Short-lived (15 min) bearer token. Memory-only — never persisted.
  final String accessToken;

  final DateTime accessTokenExpiresAt;

  final UserRole role;
  final AccountStatus accountStatus;
  final ProviderStatus providerStatus;

  /// Fine-grained scopes, e.g. `appointment:create`, `records:read_granted`.
  /// Admin carries the `*:*` wildcard.
  final Set<String> scopes;

  /// Mirrors `users.permission_version`. A mismatch against the server means
  /// the token is stale and must be refreshed before a sensitive action.
  final int permissionVersion;

  final String? displayName;
  final String? phone;
  final String? email;
  final String? photoUrl;
  final String? hospitalId;

  /// Treats the token as expired slightly early, so a request is not sent with
  /// a token that dies in flight.
  bool get isAccessTokenExpired => DateTime.now()
      .isAfter(accessTokenExpiresAt.subtract(const Duration(seconds: 30)));

  bool hasScope(String scope) =>
      scopes.contains('*:*') || scopes.contains(scope);

  /// The account is usable only when active. Suspended users are routed to a
  /// terminal screen rather than being silently signed out, so they can be told
  /// why and contact support.
  bool get isUsable => accountStatus == AccountStatus.active;

  String get greetingName {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return phone ?? email ?? 'there';
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    final expiresIn = json['expiresIn'] as int?;
    final scopes =
        (json['scopes'] as List<dynamic>?)?.map((s) => s.toString()).toSet() ??
            const <String>{};

    return Session(
      userId: json['userId'] as String,
      sessionId: json['sessionId'] as String,
      accessToken: json['accessToken'] as String,
      accessTokenExpiresAt: expiresIn != null
          ? DateTime.now().add(Duration(seconds: expiresIn))
          : DateTime.parse(json['accessTokenExpiresAt'] as String),
      role: UserRole.fromWire(json['role'] as String?),
      accountStatus: AccountStatus.fromWire(json['status'] as String?),
      providerStatus:
          ProviderStatus.fromWire(json['providerStatus'] as String?),
      scopes: scopes,
      permissionVersion: (json['permissionVersion'] as int?) ?? 0,
      displayName: json['displayName'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      photoUrl: json['photoUrl'] as String?,
      hospitalId: json['hospitalId'] as String?,
    );
  }

  Session copyWith({
    String? accessToken,
    DateTime? accessTokenExpiresAt,
    UserRole? role,
    AccountStatus? accountStatus,
    ProviderStatus? providerStatus,
    Set<String>? scopes,
    int? permissionVersion,
    String? displayName,
  }) {
    return Session(
      userId: userId,
      sessionId: sessionId,
      accessToken: accessToken ?? this.accessToken,
      accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      role: role ?? this.role,
      accountStatus: accountStatus ?? this.accountStatus,
      providerStatus: providerStatus ?? this.providerStatus,
      scopes: scopes ?? this.scopes,
      permissionVersion: permissionVersion ?? this.permissionVersion,
      displayName: displayName ?? this.displayName,
      phone: phone,
      email: email,
      photoUrl: photoUrl,
      hospitalId: hospitalId,
    );
  }
}
