library;

/// Platform-split opt-in to credentialed browser requests.
///
/// `enableBrowserCredentials(Dio)` sets `withCredentials` on the browser
/// adapter so the `HttpOnly` refresh cookie is sent to, and accepted from, the
/// API. It is a no-op on `dart:io` targets, where there is no browser to ask.
///
/// Same seam pattern as `socket_error.dart` and `certificate_pinning.dart`:
/// `api_client.dart` is reachable from `main()` on every target, so it cannot
/// import `package:dio/browser.dart` directly.
export 'browser_credentials_stub.dart'
    if (dart.library.js_interop) 'browser_credentials_web.dart';
