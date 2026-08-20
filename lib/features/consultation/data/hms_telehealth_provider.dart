import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hmssdk_flutter/hmssdk_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import 'telehealth_provider.dart';

/// 100ms implementation of [TelehealthProvider].
///
/// Chosen for India: India-region infrastructure (data residency and low RTT),
/// a maintained first-party Flutter SDK, and — decisively for FR-TEL-003 —
/// recording that can be disabled at the room-template level, so it is off by
/// vendor configuration and not by developer discipline.
///
/// This is the only file in the app that imports `hmssdk_flutter`.
class HmsTelehealthProvider implements TelehealthProvider, HMSUpdateListener {
  HmsTelehealthProvider({required ApiClient api}) : _api = api;

  final ApiClient _api;
  final HMSSDK _sdk = HMSSDK();
  final _controller = StreamController<CallState>.broadcast();

  CallState _state = const CallState();
  final Map<String, HMSVideoTrack> _videoTracks = {};

  // The SDK exposes toggles, not setters, so the desired state is tracked here
  // and a toggle is issued only when it actually differs.
  bool _micEnabled = true;
  bool _cameraEnabled = true;

  @override
  Stream<CallState> get state => _controller.stream;

  void _emit(CallState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> join({
    required String consultationId,
    required String displayName,
    required bool videoEnabled,
  }) async {
    // The server mints the token only after verifying the appointment, the
    // caller, the provider's approval status and telemedicine consent. There is
    // no client-side path to a token.
    final response = await _api.post<Map<String, dynamic>>(
      '/v1/consultations/$consultationId/join-token',
    );
    final token = response['token'] as String?;
    if (token == null) {
      throw const Failure(
        kind: FailureKind.forbidden,
        message: 'You cannot join this consultation right now.',
        code: 'JOIN_TOKEN_UNAVAILABLE',
      );
    }

    await _sdk.build();
    _sdk.addUpdateListener(listener: this);

    await _sdk.join(
      config: HMSConfig(
        authToken: token,
        userName: displayName,
        // Suppresses vendor-side collection of personally identifying analytics
        // events. Consultation participants are patients; their identity is not
        // the media vendor's business.
        shouldSkipPIIEvents: true,
        captureNetworkQualityInPreview: true,
      ),
    );

    _micEnabled = true;
    _cameraEnabled = videoEnabled;
    if (!videoEnabled) {
      // Audio-only consultation: start with the camera off rather than
      // publishing a video track and muting it.
      await _sdk.toggleCameraMuteState();
    }
  }

  @override
  Future<void> leave() async {
    await _sdk.leave();
    _videoTracks.clear();
    _emit(const CallState());
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_micEnabled == enabled) return;
    await _sdk.toggleMicMuteState();
    _micEnabled = enabled;
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    if (_cameraEnabled == enabled) return;
    await _sdk.toggleCameraMuteState();
    _cameraEnabled = enabled;
  }

  /// Flips between the front and rear camera. Distinct from
  /// [setCameraEnabled], which mutes the track entirely.
  @override
  Future<void> switchCamera() async {
    await _sdk.switchCamera();
  }

  @override
  Future<void> sendMessage(String body) async {
    await _sdk.sendBroadcastMessage(message: body);
  }

  @override
  Widget? videoViewFor(CallParticipant participant) {
    final track = participant.videoTrack;
    if (track is! HMSVideoTrack) return null;
    return HMSVideoView(
      track: track,
      // Mirror only the local preview: a mirrored remote feed makes any text
      // the other person holds up unreadable.
      setMirror: participant.isLocal,
      scaleType: ScaleType.SCALE_ASPECT_FILL,
    );
  }

  @override
  Future<void> dispose() async {
    _sdk.removeUpdateListener(listener: this);
    await _controller.close();
  }

  // --- HMSUpdateListener ----------------------------------------------------

  @override
  void onJoin({required HMSRoom room}) {
    _emit(_state.copyWith(
      isConnected: true,
      isReconnecting: false,
      participants: _participantsFrom(room),
    ));
  }

  @override
  void onPeerUpdate({required HMSPeer peer, required HMSPeerUpdate update}) {
    if (update == HMSPeerUpdate.peerLeft) {
      _videoTracks.remove(peer.peerId);
    }
    _emit(_state.copyWith(participants: _rebuildParticipants(peer, update)));
  }

  @override
  void onTrackUpdate({
    required HMSTrack track,
    required HMSTrackUpdate trackUpdate,
    required HMSPeer peer,
  }) {
    if (track.kind == HMSTrackKind.kHMSTrackKindVideo) {
      if (trackUpdate == HMSTrackUpdate.trackRemoved) {
        _videoTracks.remove(peer.peerId);
      } else {
        _videoTracks[peer.peerId] = track as HMSVideoTrack;
      }
    }
    _emit(_state.copyWith(participants: _rebuildParticipants(peer, null)));
  }

  @override
  void onHMSError({required HMSException error}) {
    if (kDebugMode) debugPrint('100ms error: ${error.message}');
    _emit(_state.copyWith(error: error.message));
  }

  @override
  void onRoomUpdate({required HMSRoom room, required HMSRoomUpdate update}) {}

  @override
  void onMessage({required HMSMessage message}) {}

  @override
  void onUpdateSpeakers({required List<HMSSpeaker> updateSpeakers}) {}

  @override
  void onReconnecting() => _emit(_state.copyWith(isReconnecting: true));

  @override
  void onReconnected() => _emit(_state.copyWith(isReconnecting: false));

  @override
  void onRoleChangeRequest({required HMSRoleChangeRequest roleChangeRequest}) {}

  @override
  void onChangeTrackStateRequest({
    required HMSTrackChangeRequest hmsTrackChangeRequest,
  }) {}

  @override
  void onRemovedFromRoom({
    required HMSPeerRemovedFromPeer hmsPeerRemovedFromPeer,
  }) {
    _emit(const CallState());
  }

  @override
  void onAudioDeviceChanged({
    HMSAudioDevice? currentAudioDevice,
    List<HMSAudioDevice>? availableAudioDevice,
  }) {}

  @override
  void onSessionStoreAvailable({HMSSessionStore? hmsSessionStore}) {}

  @override
  void onPeerListUpdate({
    required List<HMSPeer> addedPeers,
    required List<HMSPeer> removedPeers,
  }) {}

  // --- mapping --------------------------------------------------------------

  List<CallParticipant> _participantsFrom(HMSRoom room) =>
      room.peers?.map(_toParticipant).toList() ?? const [];

  List<CallParticipant> _rebuildParticipants(HMSPeer peer, HMSPeerUpdate? u) {
    final byId = {for (final p in _state.participants) p.id: p};
    if (u == HMSPeerUpdate.peerLeft) {
      byId.remove(peer.peerId);
    } else {
      byId[peer.peerId] = _toParticipant(peer);
    }
    return byId.values.toList();
  }

  CallParticipant _toParticipant(HMSPeer peer) => CallParticipant(
        id: peer.peerId,
        name: peer.name,
        isLocal: peer.isLocal,
        isAudioMuted: peer.audioTrack?.isMute ?? false,
        isVideoMuted: peer.videoTrack?.isMute ?? true,
        videoTrack: _videoTracks[peer.peerId] ?? peer.videoTrack,
      );
}

/// Stand-in used until the API can mint join tokens.
///
/// Reports a connected call with no media, so the consultation screen, its
/// controls, chat and the audio-fallback path can all be exercised without a
/// vendor account.
class FixtureTelehealthProvider implements TelehealthProvider {
  final _controller = StreamController<CallState>.broadcast();
  CallState _state = const CallState();

  @override
  Stream<CallState> get state => _controller.stream;

  @override
  Future<void> join({
    required String consultationId,
    required String displayName,
    required bool videoEnabled,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _state = CallState(
      isConnected: true,
      participants: [
        CallParticipant(id: 'local', name: displayName, isLocal: true),
        const CallParticipant(id: 'remote', name: 'Doctor', isLocal: false),
      ],
    );
    _controller.add(_state);
  }

  @override
  Future<void> leave() async {
    _state = const CallState();
    _controller.add(_state);
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> setCameraEnabled(bool enabled) async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> sendMessage(String body) async {}

  @override
  Widget? videoViewFor(CallParticipant participant) => null;

  @override
  Future<void> dispose() async => _controller.close();
}
