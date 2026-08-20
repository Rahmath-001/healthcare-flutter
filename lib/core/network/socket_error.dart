library;

/// Platform-independent access to `SocketException`.
///
/// `problem_json.dart` is reachable from `main()` on every target, so it cannot
/// import `dart:io` — doing so makes the whole web build fail to compile. The
/// one thing it needs from that library is a type test, so that is all this
/// seam exposes.
export 'socket_error_stub.dart' if (dart.library.io) 'socket_error_io.dart';
