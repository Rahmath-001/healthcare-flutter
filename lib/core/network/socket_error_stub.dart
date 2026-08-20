/// Web has no `dart:io`, and therefore no `SocketException`. A connection
/// failure in a browser surfaces as `DioExceptionType.connectionError`, which
/// is classified before this check is ever reached.
bool isSocketException(Object? error) => false;
