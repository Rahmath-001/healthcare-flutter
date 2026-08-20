import 'package:dio/dio.dart';

import 'problem_json.dart';
import 'refresh_coordinator.dart';

/// Marks a request as not needing (or not tolerating) an Authorization header.
/// Used by the session-exchange and refresh endpoints themselves, which would
/// otherwise recurse.
const kSkipAuthExtra = 'skipAuth';

/// Injects the access token, and on 401/TOKEN_STALE refreshes once and retries.
///
/// Retry happens at most once per request. If the refresh itself fails, the
/// original failure is surfaced and [onAuthenticationLost] fires so the app can
/// route back to sign-in.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.accessTokenProvider,
    required this.refresh,
    required this.coordinator,
    required this.retryClient,
    required this.onAuthenticationLost,
  });

  /// Current in-memory access token, or null when signed out.
  final String? Function() accessTokenProvider;

  /// Performs the refresh. Must update whatever [accessTokenProvider] reads.
  final Future<void> Function() refresh;

  final RefreshCoordinator coordinator;

  /// Used to replay the original request after a successful refresh. This is a
  /// bare Dio without this interceptor attached, so a replay can never loop.
  final Dio retryClient;

  final void Function() onAuthenticationLost;

  static const _retriedFlag = 'authRetried';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (options.extra[kSkipAuthExtra] != true) {
      final token = accessTokenProvider();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;

    final shouldAttemptRefresh =
        ProblemJson.isTokenExpiredOrStale(err.response) &&
            options.extra[kSkipAuthExtra] != true &&
            options.extra[_retriedFlag] != true;

    if (!shouldAttemptRefresh) {
      return handler.next(err);
    }

    try {
      // Single-flight: concurrent 401s collapse into one refresh call.
      await coordinator.run(refresh);
    } catch (_) {
      onAuthenticationLost();
      return handler.next(err);
    }

    final token = accessTokenProvider();
    if (token == null) {
      onAuthenticationLost();
      return handler.next(err);
    }

    try {
      final retried = await retryClient.fetch<dynamic>(
        options
          ..headers['Authorization'] = 'Bearer $token'
          // Guarantees a single retry: a second 401 falls through to the caller.
          ..extra[_retriedFlag] = true,
      );
      return handler.resolve(retried);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }
}
