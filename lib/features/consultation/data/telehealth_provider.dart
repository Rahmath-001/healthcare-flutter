import 'package:flutter/widgets.dart';

import '../../../core/error/failure.dart';
import '../domain/consultation.dart';

/// A participant in a live call.
@immutable
class CallParticipant {
  const CallParticipant({
    required this.id,
    required this.name,
    required this.isLocal,
    this.isAudioMuted = false,
    this.isVideoMuted = false,
    this.videoTrack,
  });

  final String id;
  final String name;
  final bool isLocal;
  final bool isAudioMuted;
  final bool isVideoMuted;

  /// Vendor-specific video track. Kept as `Object?` on purpose so nothing
  /// outside the vendor implementation and its own view widget needs to know
  /// the SDK's types.
  final Object? videoTrack;
}

/// Live call state, vendor-agnostic.
@immutable
class CallState {
  const CallState({
    this.isConnected = false,
    this.isReconnecting = false,
    this.participants = const [],
    this.quality = NetworkQuality.good,
    this.error,
  });

  final bool isConnected;
  final bool isReconnecting;
  final List<CallParticipant> participants;
  final NetworkQuality quality;
  final String? error;

  CallParticipant? get local =>
      participants.where((p) => p.isLocal).firstOrNull;

  CallParticipant? get remote =>
      participants.where((p) => !p.isLocal).firstOrNull;

  CallState copyWith({
    bool? isConnected,
    bool? isReconnecting,
    List<CallParticipant>? participants,
    NetworkQuality? quality,
    String? error,
  }) =>
      CallState(
        isConnected: isConnected ?? this.isConnected,
        isReconnecting: isReconnecting ?? this.isReconnecting,
        participants: participants ?? this.participants,
        quality: quality ?? this.quality,
        error: error,
      );
}

/// The entire surface the media vendor is allowed to occupy.
///
/// Deliberately small: mint-token, join, leave, mute, and render. 100ms is the
/// first implementation; a move to self-hosted LiveKit later replaces this file
/// and nothing else. No screen imports a vendor SDK type.
///
/// **Recording is not part of this interface, and never will be.** FR-TEL-003
/// forbids it, the room template disables it server-side, and the database has
/// a CHECK constraint. There is deliberately no method to turn it on.
abstract class TelehealthProvider {
  /// Connects to the room for [consultationId].
  ///
  /// The join token is minted by the MiDoctor API, never here: it is signed
  /// with the vendor app secret, and a secret shipped in the client would let
  /// anyone join any consultation. The server issues it only after checking
  /// the appointment is confirmed, the caller is a participant, the provider is
  /// approved, and telemedicine consent exists.
  Future<void> join({
    required String consultationId,
    required String displayName,
    required bool videoEnabled,
  });

  Future<void> leave();

  Future<void> setMicrophoneEnabled(bool enabled);

  Future<void> setCameraEnabled(bool enabled);

  Future<void> switchCamera();

  /// Sends a chat message over the vendor's data channel.
  ///
  /// The message is also relayed to our own database: retention of the
  /// consultation record is our obligation, not the vendor's.
  Future<void> sendMessage(String body);

  /// Live call state.
  Stream<CallState> get state;

  /// Renders a participant's video. Returns null when there is no track —
  /// audio-only, camera off, or not yet connected.
  Widget? videoViewFor(CallParticipant participant);

  Future<void> dispose();
}

/// Stands in on platforms where no media SDK exists.
///
/// 100ms ships Android and iOS implementations only. Its Dart surface is
/// method channels, so a web build *compiles* against it perfectly happily and
/// then throws `MissingPluginException` the moment a patient taps Join — an
/// unhandled crash on the most clinically sensitive screen in the app.
///
/// Binding this instead turns that into an ordinary [Failure] the consultation
/// screen already knows how to render, telling the user to open the app on
/// their phone rather than leaving them staring at a dead room.
class UnsupportedTelehealthProvider implements TelehealthProvider {
  const UnsupportedTelehealthProvider();

  static const _failure = Failure(
    kind: FailureKind.unknown,
    message: 'Video consultations are only available in the MiDoctor app on '
        'Android or iOS. Please join from your phone.',
    code: 'TELEHEALTH_UNSUPPORTED_PLATFORM',
  );

  @override
  Future<void> join({
    required String consultationId,
    required String displayName,
    required bool videoEnabled,
  }) async =>
      throw _failure;

  /// Leaving a call that was never joined is a no-op, not an error: the call
  /// controller runs [leave] on dispose regardless of how the screen was left.
  @override
  Future<void> leave() async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async => throw _failure;

  @override
  Future<void> setCameraEnabled(bool enabled) async => throw _failure;

  @override
  Future<void> switchCamera() async => throw _failure;

  @override
  Future<void> sendMessage(String body) async => throw _failure;

  @override
  Stream<CallState> get state => const Stream<CallState>.empty();

  @override
  Widget? videoViewFor(CallParticipant participant) => null;

  @override
  Future<void> dispose() async {}
}
