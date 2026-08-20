import 'package:flutter/foundation.dart';

/// Why a request failed, in terms the UI can branch on.
///
/// Deliberately coarse: screens should switch on this, not on HTTP status
/// codes. Anything finer belongs in [Failure.code], which carries the server's
/// machine-readable reason.
enum FailureKind {
  /// No usable connection, DNS failure, or the request timed out.
  network,

  /// Server said the caller is not authenticated (401).
  unauthenticated,

  /// Authenticated, but not allowed (403). In this app that usually means a
  /// missing scope or an expired/revoked consent grant.
  forbidden,

  /// 404.
  notFound,

  /// 409 — e.g. the slot was taken between reading and booking.
  conflict,

  /// 422 / 400 — request rejected by validation.
  validation,

  /// 429.
  rateLimited,

  /// 5xx.
  server,

  /// Anything we could not classify.
  unknown,
}

/// A normalised, user-presentable error.
///
/// Every layer above the network client deals in [Failure], never in
/// DioException or raw status codes.
@immutable
class Failure implements Exception {
  const Failure({
    required this.kind,
    required this.message,
    this.code,
    this.fieldErrors = const {},
    this.requestId,
    this.retryAfter,
  });

  final FailureKind kind;

  /// Safe to show to a user. Never contains PHI or server internals.
  final String message;

  /// Machine-readable reason from the server, e.g. `SLOT_TAKEN`,
  /// `CONSENT_EXPIRED`, `PROVIDER_NOT_APPROVED`.
  final String? code;

  /// Field-level validation messages, keyed by field name.
  final Map<String, String> fieldErrors;

  /// Server request id, for support tickets and log correlation.
  final String? requestId;

  /// Populated for [FailureKind.rateLimited] when the server sends Retry-After.
  final Duration? retryAfter;

  /// Whether retrying the same request unchanged could plausibly succeed.
  bool get isRetryable =>
      kind == FailureKind.network ||
      kind == FailureKind.server ||
      kind == FailureKind.rateLimited;

  @override
  String toString() =>
      'Failure(${kind.name}${code != null ? ', $code' : ''}): $message';
}
