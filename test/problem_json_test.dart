import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/network/problem_json.dart';

Response<dynamic> response(int status,
        {Object? body, Map<String, String>? headers}) =>
    Response<dynamic>(
      requestOptions: RequestOptions(path: '/v1/test'),
      statusCode: status,
      data: body,
      headers: Headers.fromMap({
        for (final e in (headers ?? const <String, String>{}).entries)
          e.key: [e.value],
      }),
    );

DioException dioError(DioExceptionType type, {Response<dynamic>? res}) =>
    DioException(
      requestOptions: RequestOptions(path: '/v1/test'),
      type: type,
      response: res,
    );

void main() {
  group('transport errors', () {
    test('timeouts map to network', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final f = ProblemJson.fromDioException(dioError(t));
        expect(f.kind, FailureKind.network, reason: t.name);
        expect(f.isRetryable, isTrue);
      }
    });

    test('a bad certificate is never presented as retryable noise', () {
      final f = ProblemJson.fromDioException(
          dioError(DioExceptionType.badCertificate));
      expect(f.code, 'BAD_CERTIFICATE');
      expect(f.kind, FailureKind.network);
    });

    test('cancellation is not surfaced as an error kind', () {
      final f = ProblemJson.fromDioException(dioError(DioExceptionType.cancel));
      expect(f.code, 'CANCELLED');
      expect(f.isRetryable, isFalse);
    });
  });

  group('status mapping', () {
    final cases = <int, FailureKind>{
      401: FailureKind.unauthenticated,
      403: FailureKind.forbidden,
      404: FailureKind.notFound,
      409: FailureKind.conflict,
      400: FailureKind.validation,
      422: FailureKind.validation,
      429: FailureKind.rateLimited,
      500: FailureKind.server,
      503: FailureKind.server,
    };

    cases.forEach((status, kind) {
      test('$status -> ${kind.name}', () {
        expect(ProblemJson.fromResponse(response(status)).kind, kind);
      });
    });
  });

  group('RFC 9457 body', () {
    test('extracts detail, code, requestId and field errors', () {
      final f = ProblemJson.fromResponse(response(409, body: {
        'type': 'https://midoctor.in/errors/slot-taken',
        'title': 'Slot no longer available',
        'status': 409,
        'detail': 'Someone booked this slot first.',
        'code': 'SLOT_TAKEN',
        'requestId': '01JABC',
        'errors': {'slotId': 'no longer available'},
      }));

      expect(f.kind, FailureKind.conflict);
      expect(f.code, 'SLOT_TAKEN');
      expect(f.message, 'Someone booked this slot first.');
      expect(f.requestId, '01JABC');
      expect(f.fieldErrors['slotId'], 'no longer available');
    });

    test('falls back to title, then to a generic message', () {
      expect(
        ProblemJson.fromResponse(
            response(403, body: {'title': 'Consent expired'})).message,
        'Consent expired',
      );
      expect(
        ProblemJson.fromResponse(response(403)).message,
        'You do not have access to this.',
      );
    });

    test('a non-map body never leaks into the message', () {
      // Guards against dumping a raw payload, which could carry clinical text.
      final f =
          ProblemJson.fromResponse(response(500, body: 'PATIENT RECORD DUMP'));
      expect(f.message, isNot(contains('PATIENT')));
      expect(f.kind, FailureKind.server);
    });

    test('reads Retry-After on 429', () {
      final f = ProblemJson.fromResponse(
          response(429, headers: {'retry-after': '30'}));
      expect(f.retryAfter, const Duration(seconds: 30));
    });
  });

  group('token staleness', () {
    test('a 401 counts as expired-or-stale', () {
      expect(ProblemJson.isTokenExpiredOrStale(response(401)), isTrue);
    });

    test('TOKEN_STALE counts even on a non-401', () {
      // The server signals a permission_version mismatch this way: the token is
      // valid but the role/status/scopes behind it changed.
      expect(
        ProblemJson.isTokenExpiredOrStale(
            response(409, body: {'code': 'TOKEN_STALE'})),
        isTrue,
      );
    });

    test('an ordinary error does not trigger a refresh', () {
      expect(
        ProblemJson.isTokenExpiredOrStale(
            response(403, body: {'code': 'CONSENT_EXPIRED'})),
        isFalse,
      );
      expect(ProblemJson.isTokenExpiredOrStale(null), isFalse);
    });
  });
}
