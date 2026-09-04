import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/network/api_client.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  test('surfaces a 5xx response without substituting local records', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    final adapter = DioAdapter(dio: dio);
    final api = ApiClient(dio: dio);
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

  });

  test('surfaces a real authorization refusal', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    final adapter = DioAdapter(dio: dio);
    final api = ApiClient(dio: dio);
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

  });
}
