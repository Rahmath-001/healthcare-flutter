@TestOn('vm')
library;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/config/app_config.dart';
import 'package:healthcare_mobile/core/network/api_client.dart';

/// Certificate pinning wiring.
///
/// The pin *values* cannot be asserted here — that needs a real handshake — but
/// the two things that actually go wrong can be:
///
///  1. pinning silently not applied, so a build believes it is pinned and is
///     not; and
///  2. pinning applied when no pins are configured, which is how a fleet
///     bricks itself.
///
/// Both are structural, and both are invisible until the day they matter.
void main() {
  AppConfig config({Set<String> pins = const {}}) => AppConfig(
        env: AppEnv.prod,
        apiBaseUrl: 'https://api.midoctor.in',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        certificatePins: pins,
      );

  test('no pins configured leaves the default adapter untouched', () {
    final dio = buildDio(config());

    // The kill switch. An empty set must mean "behave exactly as before",
    // because shipping a build with the pins removed is the only way to
    // recover a fleet that cannot reach its own API.
    final adapter = dio.httpClientAdapter;
    expect(
      adapter is IOHttpClientAdapter && adapter.validateCertificate != null,
      isFalse,
    );
  });

  test('configured pins install a leaf-certificate validator', () {
    final dio = buildDio(config(pins: {'AAAA', 'BBBB'}));

    final adapter = dio.httpClientAdapter;
    expect(adapter, isA<IOHttpClientAdapter>());
    expect((adapter as IOHttpClientAdapter).validateCertificate, isNotNull);
  });

  test('a null certificate is refused when pins are configured', () {
    final dio = buildDio(config(pins: {'AAAA'}));
    final validate =
        (dio.httpClientAdapter as IOHttpClientAdapter).validateCertificate!;

    // No certificate to inspect means no TLS handshake happened. With pinning
    // on, that is a refusal — never a pass-through.
    expect(validate(null, 'api.midoctor.in', 443), isFalse);
  });

  test('the replay client is pinned too', () {
    // `retryDioProvider` builds a bare Dio with no AuthInterceptor so a replay
    // cannot recurse. It reaches the same API, so an unpinned replay path would
    // be a hole in the pin rather than an exception to it.
    final dio = buildDio(config(pins: {'AAAA'}));
    expect(dio.interceptors.whereType<QueuedInterceptor>(), isEmpty);
    expect(
      (dio.httpClientAdapter as IOHttpClientAdapter).validateCertificate,
      isNotNull,
    );
  });

  test('dev declares no pins so a debug proxy keeps working', () {
    // Matches the debug-overrides block in network_security_config.xml, which
    // trusts user-installed CAs for the same reason.
    expect(
      const AppConfig(
        env: AppEnv.dev,
        apiBaseUrl: 'http://10.0.2.2:8080',
        connectTimeout: Duration(seconds: 10),
        receiveTimeout: Duration(seconds: 30),
      ).certificatePins,
      isEmpty,
    );
  });
}
