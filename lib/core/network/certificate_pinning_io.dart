import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../config/app_config.dart';

/// Pins the API's TLS leaf certificate, on top of normal PKI validation.
///
/// Dio's `validateCertificate` runs **after** the chain, hostname and validity
/// checks have already passed, and evaluates the leaf. That layering is the
/// whole design: this adds a constraint, it never replaces one. The common
/// wrong implementation builds a `SecurityContext(withTrustedRoots: false)` and
/// accepts anything whose fingerprint matches — which silently discards expiry
/// and hostname checking in exchange for the pin.
///
/// ## Why this did not exist before
///
/// A pin is the only security control that can brick an installed fleet. When
/// the certificate is renewed, every build carrying only the old pin stops
/// being able to reach the API at all — and it cannot be fixed by a server
/// deploy, only by an app update that users have to install, which is exactly
/// the population you can no longer reach. Three things make it survivable, and
/// all three are here:
///
///  1. **Backup pins.** [AppConfig.certificatePins] holds a set, not a value.
///     The next certificate's pin ships *before* the rotation, so both the
///     current and the next leaf validate during the changeover.
///  2. **A kill switch.** An empty pin set disables pinning. Ship a build with
///     pins removed and the fleet recovers without waiting for a correct pin.
///  3. **Fail-open on dev.** Only `staging` and `prod` declare pins at all, so
///     a proxy on a developer machine keeps working.
///
/// Rotation runbook: add the new pin alongside the old, ship, wait for adoption,
/// rotate the certificate, then drop the old pin in a later release. Never
/// replace a pin in a single step.
void applyPinning(Dio dio, AppConfig config) {
  final pins = config.certificatePins;
  if (pins.isEmpty) return;

  dio.httpClientAdapter = IOHttpClientAdapter(
    validateCertificate: (certificate, host, port) {
      // A null certificate means there was no TLS handshake to inspect. With
      // pins configured, that is a refusal rather than a pass: the only way to
      // reach here without one is a cleartext connection, which the platform
      // configuration already forbids.
      if (certificate == null) return false;
      return pins.contains(pinOf(certificate));
    },
  );
}

/// The pin for a certificate: base64 of the SHA-256 of its DER encoding.
///
/// This pins the **leaf certificate**, not its public key. `dart:io`'s
/// `X509Certificate` exposes the DER but not the SubjectPublicKeyInfo, and
/// parsing ASN.1 by hand to extract the SPKI is a worse trade than accepting
/// the consequence — which is that the pin changes on every renewal even when
/// the key is reused. The backup-pin rotation above is what makes that
/// workable, and it is a discipline worth having regardless.
///
/// Generate one for a host with:
/// ```sh
/// openssl s_client -connect api.midoctor.in:443 -servername api.midoctor.in \
///   </dev/null 2>/dev/null | openssl x509 -outform der | openssl dgst -sha256 -binary | base64
/// ```
String pinOf(X509Certificate certificate) =>
    base64.encode(sha256.convert(certificate.der).bytes);
