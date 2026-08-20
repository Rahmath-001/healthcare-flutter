import 'package:flutter/foundation.dart';

/// Build-time environment. Selected with --dart-define=ENV=staging (etc.) so a
/// single codebase produces dev/staging/prod artifacts without code changes.
enum AppEnv { dev, staging, prod }

/// Immutable, compile-time app configuration.
///
/// Nothing secret belongs here: everything in this class ships inside the app
/// bundle and is readable by anyone who unzips the APK. API keys that must stay
/// private live on the server.
@immutable
class AppConfig {
  const AppConfig({
    required this.env,
    required this.apiBaseUrl,
    required this.connectTimeout,
    required this.receiveTimeout,
  });

  final AppEnv env;

  /// Base URL of the MiDoctor API (not Firebase). Phase 1 introduces
  /// `POST /v1/auth/session`, which exchanges a Firebase ID token for a
  /// MiDoctor session.
  final String apiBaseUrl;

  final Duration connectTimeout;
  final Duration receiveTimeout;

  bool get isProd => env == AppEnv.prod;

  /// Reads --dart-define values, falling back to dev defaults so a fresh
  /// checkout runs with no extra flags.
  factory AppConfig.fromEnvironment() {
    const envName = String.fromEnvironment('ENV', defaultValue: 'dev');
    final env = switch (envName) {
      'prod' => AppEnv.prod,
      'staging' => AppEnv.staging,
      _ => AppEnv.dev,
    };

    const baseUrl = String.fromEnvironment('API_BASE_URL');

    return AppConfig(
      env: env,
      apiBaseUrl: baseUrl.isNotEmpty ? baseUrl : _defaultBaseUrl(env),
      // Indian mobile networks are frequently slow rather than absent; a short
      // connect timeout with a longer receive timeout fails fast on genuinely
      // dead links without aborting a working-but-slow response.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    );
  }

  static String _defaultBaseUrl(AppEnv env) => switch (env) {
        // 10.0.2.2 is the host loopback as seen from the Android emulator.
        AppEnv.dev => 'http://10.0.2.2:8080',
        AppEnv.staging => 'https://api-staging.midoctor.in',
        AppEnv.prod => 'https://api.midoctor.in',
      };
}
