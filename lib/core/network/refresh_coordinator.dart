import 'dart:async';

/// Serialises token refreshes so that N concurrent 401s cause exactly ONE
/// refresh call.
///
/// Without this, a screen that fires several requests at once (appointments +
/// records + profile) hits the refresh endpoint several times in parallel. With
/// rotating refresh tokens and reuse detection on the server, the second call
/// presents an already-rotated token, which the server correctly interprets as
/// theft and revokes the entire session family — logging the user out for doing
/// nothing wrong.
///
/// Callers await [run]; the first caller performs the refresh and every
/// concurrent caller awaits that same future.
class RefreshCoordinator {
  Future<void>? _inFlight;

  /// True while a refresh is running. Exposed for tests and diagnostics.
  bool get isRefreshing => _inFlight != null;

  /// Runs [refresh] unless one is already in flight, in which case it awaits
  /// the in-flight attempt instead of starting a second one.
  ///
  /// If the refresh throws, the error propagates to *every* awaiting caller and
  /// the slot is cleared so a later attempt can try again.
  Future<void> run(Future<void> Function() refresh) {
    final existing = _inFlight;
    if (existing != null) return existing;

    // whenComplete (not then) so the slot is released on both success and
    // failure, and assignment happens before any await point.
    final future = refresh().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }
}
