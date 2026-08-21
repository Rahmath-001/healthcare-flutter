import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Web build: certificate pinning is not expressible.
///
/// The browser performs TLS itself and never hands the peer certificate to
/// script, so there is nothing to compare a pin against. This is a genuine
/// platform limitation rather than an omission, and it is recorded as a gap in
/// `docs/SECURITY_AUDIT.md` rather than papered over — a no-op that pretends to
/// pin is worse than no pinning, because someone will read the call site and
/// believe the connection is pinned.
void applyPinning(Dio dio, AppConfig config) {}
