// `package:meta`, not `package:flutter/foundation`, for `@immutable`: this
// class is pure configuration with no Flutter dependency, and importing
// foundation drags in `dart:ui`, which makes the file unloadable from a plain
// `dart run`. `tool/check_release_config.dart` is exactly that.
import 'package:meta/meta.dart';

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
    this.certificatePins = const {},
  });

  final AppEnv env;

  /// Base URL of the MiDoctor API (not Firebase). Phase 1 introduces
  /// `POST /v1/auth/session`, which exchanges a Firebase ID token for a
  /// MiDoctor session.
  final String apiBaseUrl;

  final Duration connectTimeout;
  final Duration receiveTimeout;

  /// Accepted TLS leaf-certificate pins for [apiBaseUrl], as base64 SHA-256 of
  /// the DER encoding. See `certificate_pinning_io.dart` for how to generate
  /// one and for the rotation runbook.
  ///
  /// **An empty set disables pinning**, and that is the kill switch: a pin is
  /// the one control that can make an installed app permanently unable to reach
  /// its own API, and the recovery path has to be a build you can ship rather
  /// than a fix users must install before they can be fixed.
  ///
  /// A pin is a hash of a public certificate. It is not a secret, and shipping
  /// it in the bundle — where everything in this class is readable — costs
  /// nothing.
  final Set<String> certificatePins;

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
      certificatePins: pinsForEnvironment(env),
    );
  }

  /// Pins per environment.
  ///
  /// Dev declares none on purpose: a developer running mitmproxy against the
  /// emulator is doing so deliberately, and the debug network-security config
  /// already trusts user CAs for the same reason.
  ///
  /// **Staging and prod are empty pending the real certificates.** They are
  /// wired end to end and enforced the moment a value lands here, which is the
  /// point — the mechanism is not the thing anyone forgets, the value is. Fill
  /// these from the deployed certificate before the first external release, and
  /// always keep two: the live one and its successor.
  static Set<String> pinsForEnvironment(AppEnv env) => switch (env) {
        AppEnv.dev => const {},
        AppEnv.staging => const {},
        AppEnv.prod => const {},
      };

  static String _defaultBaseUrl(AppEnv env) => switch (env) {
        // 10.0.2.2 is the host loopback as seen from the Android emulator.
        AppEnv.dev => 'http://10.0.2.2:8080',
        AppEnv.staging => 'https://api-staging.midoctor.in',
        AppEnv.prod => 'https://api.midoctor.in',
      };
}
