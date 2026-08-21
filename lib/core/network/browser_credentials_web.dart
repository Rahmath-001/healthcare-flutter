import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// Sends and accepts cookies on cross-origin API calls.
///
/// Without this the browser silently drops the `HttpOnly` refresh cookie on
/// both legs — it is not attached to the request and `Set-Cookie` on the
/// response is ignored — so refresh would fail with no visible cause beyond a
/// 401. It pairs with `credentials: true` and an explicit origin allow-list in
/// the API's CORS configuration; a wildcard origin with credentials is refused
/// by every browser, which is the spec protecting us from ourselves.
void enableBrowserCredentials(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is BrowserHttpClientAdapter) {
    adapter.withCredentials = true;
  }
}
