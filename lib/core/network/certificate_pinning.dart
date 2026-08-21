library;

/// Platform-split certificate pinning.
///
/// `applyPinning(Dio, AppConfig)` layers a leaf-certificate pin on top of the
/// platform's normal chain validation on `dart:io` targets, and does nothing on
/// web — where the browser owns TLS and never exposes the peer certificate to
/// script, so a pin cannot be expressed at all.
///
/// Same seam pattern as `socket_error.dart`: `api_client.dart` is reachable
/// from `main()` on every target, so it must not import `dart:io` directly.
///
/// See `certificate_pinning_io.dart` for the rotation runbook — a pin is the
/// one control capable of bricking an installed fleet, and it is only safe with
/// backup pins and a kill switch.
export 'certificate_pinning_stub.dart'
    if (dart.library.io) 'certificate_pinning_io.dart';
