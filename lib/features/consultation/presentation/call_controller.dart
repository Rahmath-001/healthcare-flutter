import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../data/telehealth_provider.dart';

/// Drives one live call: connect, mute, camera, hang up.
///
/// Owns the media session so the screen stays a view. Leaving is idempotent and
/// runs on dispose, because a call left running after the screen is gone keeps
/// the microphone hot — which on a medical consultation is unacceptable, not
/// merely untidy.
class CallController extends Notifier<CallState> {
  StreamSubscription<CallState>? _sub;

  TelehealthProvider get _provider => ref.read(telehealthProviderProvider);

  @override
  CallState build() {
    _sub = _provider.state.listen((s) => state = s);
    ref.onDispose(() {
      _sub?.cancel();
      // Fire-and-forget: dispose cannot await, but the microphone must stop.
      unawaited(_provider.leave());
    });
    return const CallState();
  }

  Future<void> join({
    required String consultationId,
    required String displayName,
    required bool videoEnabled,
  }) =>
      _provider.join(
        consultationId: consultationId,
        displayName: displayName,
        videoEnabled: videoEnabled,
      );

  Future<void> setMicrophoneEnabled(bool enabled) =>
      _provider.setMicrophoneEnabled(enabled);

  Future<void> setCameraEnabled(bool enabled) =>
      _provider.setCameraEnabled(enabled);

  Future<void> switchCamera() => _provider.switchCamera();

  Future<void> sendMessage(String body) => _provider.sendMessage(body);

  Future<void> leave() => _provider.leave();
}

/// autoDispose so leaving the screen tears the media session down. A call left
/// running after its screen is gone keeps the microphone open.
final callControllerProvider =
    NotifierProvider.autoDispose<CallController, CallState>(
  CallController.new,
);
