import 'package:dio/dio.dart';

import '../error/failure.dart';
import 'socket_error.dart';

/// Sentinel returned by the API when the access token's `ver` claim is behind
/// the user's current permission_version — i.e. the token is valid but stale
/// because a role, status, or scope changed.
///
/// The auth interceptor treats this exactly like a 401: refresh, then retry.
const kTokenStaleCode = 'TOKEN_STALE';

/// Translates transport and HTTP errors into [Failure].
///
/// The API emits RFC 9457 (`application/problem+json`) bodies:
/// ```json
/// { "type": "https://midoctor.in/errors/slot-taken",
///   "title": "Slot no longer available",
///   "status": 409,
///   "detail": "Someone booked this slot first.",
///   "code": "SLOT_TAKEN",
///   "requestId": "01J...",
///   "errors": { "slotId": "no longer available" } }
/// ```
/// Anything that does not parse as problem+json still yields a sane [Failure]
/// rather than leaking a Dio stack trace into the UI.
class ProblemJson {
  const ProblemJson._();

  static Failure fromDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const Failure(
          kind: FailureKind.network,
          message: 'The connection timed out. Please try again.',
          code: 'TIMEOUT',
        );
      case DioExceptionType.connectionError:
        return const Failure(
          kind: FailureKind.network,
          message: 'No internet connection.',
          code: 'OFFLINE',
        );
      case DioExceptionType.cancel:
        return const Failure(
          kind: FailureKind.unknown,
          message: 'Request cancelled.',
          code: 'CANCELLED',
        );
      case DioExceptionType.badCertificate:
        // Treated as fatal: a bad certificate on a health app is either a
        // misconfiguration or an interception attempt. Never retry silently.
        return const Failure(
          kind: FailureKind.network,
          message: 'Could not establish a secure connection.',
          code: 'BAD_CERTIFICATE',
        );
      case DioExceptionType.badResponse:
        return fromResponse(e.response);
      case DioExceptionType.unknown:
        if (isSocketException(e.error)) {
          return const Failure(
            kind: FailureKind.network,
            message: 'No internet connection.',
            code: 'OFFLINE',
          );
        }
        return Failure(
          kind: FailureKind.unknown,
          message: 'Something went wrong. Please try again.',
          code: 'UNKNOWN',
          requestId: _requestIdOf(e.response),
        );
    }
  }

  static Failure fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode ?? 0;
    final body = response?.data;
    final problem =
        body is Map<String, dynamic> ? body : const <String, dynamic>{};

    final kind = _kindForStatus(status);
    final code = problem['code'] as String?;

    // Prefer the server's human-readable `detail`, then `title`, then a generic
    // message keyed off the status. Never surface a raw body: it may contain
    // clinical detail that does not belong in a toast.
    final message = (problem['detail'] as String?) ??
        (problem['title'] as String?) ??
        _defaultMessageFor(kind);

    return Failure(
      kind: kind,
      message: message,
      code: code,
      fieldErrors: _fieldErrors(problem['errors']),
      requestId: (problem['requestId'] as String?) ?? _requestIdOf(response),
      retryAfter: _retryAfter(response),
    );
  }

  static FailureKind _kindForStatus(int status) => switch (status) {
        401 => FailureKind.unauthenticated,
        403 => FailureKind.forbidden,
        404 => FailureKind.notFound,
        409 => FailureKind.conflict,
        400 || 422 => FailureKind.validation,
        429 => FailureKind.rateLimited,
        >= 500 => FailureKind.server,
        _ => FailureKind.unknown,
      };

  static String _defaultMessageFor(FailureKind kind) => switch (kind) {
        FailureKind.unauthenticated => 'Please sign in again.',
        FailureKind.forbidden => 'You do not have access to this.',
        FailureKind.notFound => 'Not found.',
        FailureKind.conflict => 'That is no longer available.',
        FailureKind.validation => 'Please check the details and try again.',
        FailureKind.rateLimited => 'Too many attempts. Please wait a moment.',
        FailureKind.server => 'Server error. Please try again shortly.',
        FailureKind.network => 'Network error. Please try again.',
        FailureKind.unknown => 'Something went wrong. Please try again.',
      };

  static Map<String, String> _fieldErrors(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

  static String? _requestIdOf(Response<dynamic>? response) =>
      response?.headers.value('x-request-id');

  static Duration? _retryAfter(Response<dynamic>? response) {
    final raw = response?.headers.value('retry-after');
    if (raw == null) return null;
    final seconds = int.tryParse(raw);
    return seconds == null ? null : Duration(seconds: seconds);
  }

  /// True when the response means "your access token is no longer good, but the
  /// session may still be": either a plain 401 or a 200-shaped TOKEN_STALE.
  static bool isTokenExpiredOrStale(Response<dynamic>? response) {
    if (response == null) return false;
    if (response.statusCode == 401) return true;
    final body = response.data;
    return body is Map && body['code'] == kTokenStaleCode;
  }
}
