import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/network/api_client.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  test('notifies the composition root when the API returns a 5xx response',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    final adapter = DioAdapter(dio: dio);
    var usedFixtureFallback = false;
    final api = ApiClient(
      dio: dio,
      onServiceUnavailable: () => usedFixtureFallback = true,
    );
    adapter.onGet(
      '/v1/health',
      (server) => server.reply(503, {
        'title': 'Unavailable',
        'status': 503,
        'detail': 'Try again shortly.',
      }),
    );

    await expectLater(
      api.get<Map<String, dynamic>>('/v1/health'),
      throwsA(isA<Failure>().having((f) => f.kind, 'kind', FailureKind.server)),
    );

    expect(usedFixtureFallback, isTrue);
  });

  test('does not replace a real authorization refusal with sample data',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    final adapter = DioAdapter(dio: dio);
    var usedFixtureFallback = false;
    final api = ApiClient(
      dio: dio,
      onServiceUnavailable: () => usedFixtureFallback = true,
    );
    adapter.onGet(
      '/v1/records',
      (server) => server.reply(403, {
        'title': 'Forbidden',
        'status': 403,
        'detail': 'Access revoked.',
      }),
    );

    await expectLater(
      api.get<List<dynamic>>('/v1/records'),
      throwsA(
        isA<Failure>().having((f) => f.kind, 'kind', FailureKind.forbidden),
      ),
    );

    expect(usedFixtureFallback, isFalse);
  });
}
