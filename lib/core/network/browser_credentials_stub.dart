import 'package:dio/dio.dart';

/// Native targets: there is no browser cookie jar to opt into.
///
/// Mobile keeps the refresh token in the Keychain / KeyStore and sends it in
/// the request body, which is the stronger arrangement — this seam exists only
/// so the web build can reach parity, not because mobile is missing something.
void enableBrowserCredentials(Dio dio) {}
