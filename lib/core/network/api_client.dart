import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../error/failure.dart';
import 'browser_credentials.dart';
import 'certificate_pinning.dart';
import 'problem_json.dart';

/// Thin wrapper over Dio that guarantees callers only ever see [Failure],
/// never a [DioException].
///
/// Everything above this class — repositories, providers, widgets — is written
/// against [Failure] and knows nothing about HTTP or Dio.
class ApiClient {
  ApiClient({required this.dio});

  final Dio dio;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _guard(() =>
          dio.get<T>(path, queryParameters: query, cancelToken: cancelToken));

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    bool skipAuth = false,
  }) =>
      _guard(() => dio.post<T>(
            path,
            data: body,
            queryParameters: query,
            cancelToken: cancelToken,
            options: skipAuth ? Options(extra: const {'skipAuth': true}) : null,
          ));

  Future<T> put<T>(String path, {Object? body, CancelToken? cancelToken}) =>
      _guard(() => dio.put<T>(path, data: body, cancelToken: cancelToken));

  Future<T> patch<T>(String path, {Object? body, CancelToken? cancelToken}) =>
      _guard(() => dio.patch<T>(path, data: body, cancelToken: cancelToken));

  Future<T> delete<T>(String path, {Object? body, CancelToken? cancelToken}) =>
      _guard(() => dio.delete<T>(path, data: body, cancelToken: cancelToken));

  Future<T> _guard<T>(Future<Response<T>> Function() send) async {
    try {
      final response = await send();
      final data = response.data;
      if (data == null) {
        throw const Failure(
          kind: FailureKind.unknown,
          message: 'The server returned an empty response.',
          code: 'EMPTY_RESPONSE',
        );
      }
      return data;
    } on DioException catch (e) {
      throw ProblemJson.fromDioException(e);
    }
  }
}

/// Builds the configured Dio instance.
///
/// [interceptors] are appended after the defaults so wiring stays explicit at
/// the composition root rather than hidden in here.
Dio buildDio(AppConfig config, {List<Interceptor> interceptors = const []}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      // The API speaks RFC 9457 on errors; accept both so error bodies parse.
      headers: const {
        'Accept': 'application/json, application/problem+json',
        'Content-Type': 'application/json',
      },
      // Let non-2xx reach the error path so ProblemJson can classify it.
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );
  // Layered on top of the platform's own chain validation, never instead of
  // it, and a no-op unless the environment declares pins. Applied to every Dio
  // this function builds — including the bare replay client, which would
  // otherwise be an unpinned path to the same API.
  applyPinning(dio, config);

  // Web only: lets the browser attach the HttpOnly refresh cookie. No-op
  // everywhere else, where the token travels in the body instead.
  enableBrowserCredentials(dio);

  dio.interceptors.addAll(interceptors);
  return dio;
}
