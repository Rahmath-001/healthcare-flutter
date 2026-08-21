// Release gate for configuration that is only wrong in production.
//
// Run before shipping:
//
//     dart run tool/check_release_config.dart prod
//
// Exits non-zero with an explanation when something that must be set for an
// external release is not. This mirrors the pattern already in
// `android/app/build.gradle.kts`, where a release build fails closed without
// `key.properties` rather than quietly producing an unsigned artifact — the
// same idea applied to configuration the compiler cannot check.
//
// Why a script rather than a test: `flutter test` runs on every commit, and a
// test that fails until launch day is a test people learn to ignore. This runs
// only when someone is actually cutting a release.

import 'dart:io';

import 'package:healthcare_mobile/core/config/app_config.dart';

void main(List<String> args) {
  final envName = args.isEmpty ? 'prod' : args.first;
  final env = switch (envName) {
    'prod' => AppEnv.prod,
    'staging' => AppEnv.staging,
    'dev' => AppEnv.dev,
    _ => null,
  };

  if (env == null) {
    stderr.writeln('Unknown environment "$envName". Use dev, staging or prod.');
    exit(64);
  }

  if (env == AppEnv.dev) {
    stdout.writeln('dev: nothing to check.');
    return;
  }

  final failures = <String>[];
  final pins = AppConfig.pinsForEnvironment(env);

  if (pins.isEmpty) {
    failures.add(
      'Certificate pinning is DISABLED for $envName: AppConfig.pinsForEnvironment '
      'returns an empty set.\n'
      '  Generate the pin for the deployed certificate with:\n'
      '    openssl s_client -connect <host>:443 -servername <host> </dev/null \\\n'
      '      | openssl x509 -outform der | openssl dgst -sha256 -binary | base64\n'
      '  See lib/core/network/certificate_pinning_io.dart for the rotation '
      'runbook.',
    );
  } else if (pins.length < 2) {
    failures.add(
      'Only one certificate pin is configured for $envName.\n'
      '  Ship two: the live certificate and its successor. With a single pin, '
      'renewing the certificate makes every installed build permanently unable '
      'to reach the API, and the fix is an update those users can no longer '
      'download.',
    );
  }

  for (final pin in pins) {
    // Base64 of a SHA-256 digest is always 44 characters ending in '='. A pin
    // that is the wrong shape is a typo that would not surface until the first
    // TLS handshake in production.
    if (pin.length != 44 || !pin.endsWith('=')) {
      failures.add(
        'Malformed certificate pin for $envName: "$pin".\n'
        '  Expected base64 of a SHA-256 digest — 44 characters ending in "=".',
      );
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('$envName: release configuration OK '
        '(${pins.length} certificate pins).');
    return;
  }

  stderr.writeln('Release configuration check FAILED for $envName:\n');
  for (final f in failures) {
    stderr.writeln('  - $f\n');
  }
  exit(1);
}
