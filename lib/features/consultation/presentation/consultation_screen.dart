import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/async_view.dart';
import '../../providers_search/domain/doctor.dart';
import '../data/telehealth_provider.dart';
import '../domain/consent_text.dart';
import '../domain/consultation.dart';
import 'call_controller.dart';

final consultationProvider =
    FutureProvider.family<Consultation, String>((ref, id) async {
  return ref.watch(consultationRepositoryProvider).byId(id);
});

final networkQualityProvider =
    StreamProvider.family<NetworkQuality, String>((ref, id) {
  return ref.watch(consultationRepositoryProvider).networkQuality(id);
});

/// Icons for the consent points, positionally matched to
/// `TelemedicineConsent.points`. Kept out of the domain file so the hashed text
/// stays free of presentation.
const _consentIcons = <IconData>[
  Icons.videocam_off_outlined,
  Icons.chat_outlined,
  Icons.medical_information_outlined,
  Icons.emergency_outlined,
];

/// The consultation surface: consent gate, waiting room, live call and chat.
///
/// Media is not wired here. The vendor (100ms) sits behind a `TelehealthProvider`
/// seam whose whole surface is minting a join token, room lifecycle and
/// participant events — so this screen is the real flow with a placeholder
/// video pane, and swapping the vendor never touches it.
class ConsultationScreen extends ConsumerWidget {
  const ConsultationScreen({super.key, required this.consultationId});

  final String consultationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consultation = ref.watch(consultationProvider(consultationId));

    return Scaffold(
      body: AsyncView<Consultation>(
        value: consultation,
        onRetry: () => ref.invalidate(consultationProvider(consultationId)),
        data: (c) => switch (c.status) {
          ConsultationStatus.ended ||
          ConsultationStatus.abandoned =>
            _EndedView(consultation: c),
          _ when !c.hasConsent => _ConsentGate(consultation: c),
          ConsultationStatus.active => _LiveView(consultation: c),
          _ => _WaitingRoom(consultation: c),
        },
      ),
    );
  }
}

/// Consent must be captured before connecting.
///
/// Also the screen that satisfies the Telemedicine Practice Guidelines'
/// identity requirement: the doctor's name, qualification and registration
/// number are shown before the patient agrees to anything.
class _ConsentGate extends ConsumerStatefulWidget {
  const _ConsentGate({required this.consultation});

  final Consultation consultation;

  @override
  ConsumerState<_ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends ConsumerState<_ConsentGate> {
  bool _agreed = false;
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(consultationRepositoryProvider)
          .captureConsent(widget.consultation.id);
      ref.invalidate(consultationProvider(widget.consultation.id));
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.consultation.doctor;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 16),
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    child: Text(
                      d.name.split(' ').last[0],
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(d.name,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(d.qualification,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 2),
                Text(
                  'Registration ${d.registrationNumber}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                Text(context.l10n.consentTelemedicineTitle,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                // Rendered from `TelemedicineConsent`, which is also what gets
                // hashed into the consent record. Inlining the copy here again
                // would let the two drift, and a hash of text nobody saw is
                // not evidence of anything.
                for (var i = 0; i < TelemedicineConsent.points.length; i++)
                  _ConsentPoint(
                    icon: _consentIcons[i],
                    text: TelemedicineConsent.points[i],
                  ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(TelemedicineConsent.agreement),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _agreed && !_busy ? _accept : null,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(context.l10n.consultAgreeContinue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  const _ConsentPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _WaitingRoom extends ConsumerStatefulWidget {
  const _WaitingRoom({required this.consultation});

  final Consultation consultation;

  @override
  ConsumerState<_WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends ConsumerState<_WaitingRoom> {
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    final c = widget.consultation;
    try {
      // Domain first: this is what enforces consent and the join window. Only
      // then is a media session opened.
      await ref.read(consultationRepositoryProvider).join(c.id);
      await ref.read(callControllerProvider.notifier).join(
            consultationId: c.id,
            displayName: c.patientName,
            videoEnabled: c.mode == ConsultationMode.video,
          );
      ref.invalidate(consultationProvider(c.id));
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.consultation;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 44,
              child: Text(c.doctor.name.split(' ').last[0],
                  style: theme.textTheme.headlineMedium),
            ),
            const SizedBox(height: 20),
            Text(c.doctor.name, style: theme.textTheme.titleLarge),
            Text(c.doctor.specialtyLabel, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text('Registration ${c.doctor.registrationNumber}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 32),
            Text(
              'Scheduled for ${Fmt.dateTime(c.scheduledStart)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _joining ? null : _join,
                icon: _joining
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(c.mode == ConsultationMode.audio
                        ? Icons.call
                        : Icons.videocam),
                label: Text(_joining ? 'Connecting' : 'Join consultation'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Not recorded. Only you and your doctor take part.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveView extends ConsumerStatefulWidget {
  const _LiveView({required this.consultation});

  final Consultation consultation;

  @override
  ConsumerState<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends ConsumerState<_LiveView> {
  final _messageCtrl = TextEditingController();
  bool _chatOpen = false;
  bool _muted = false;
  bool _cameraOff = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await ref.read(callControllerProvider.notifier).setMicrophoneEnabled(!next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleCamera() async {
    final next = !_cameraOff;
    await ref.read(callControllerProvider.notifier).setCameraEnabled(!next);
    if (mounted) setState(() => _cameraOff = next);
  }

  Future<void> _end() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.consultEndQuestion),
        content: Text(context.l10n.consultEitherCanEnd),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.consultStay),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.consultationEnd),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(callControllerProvider.notifier).leave();
    await ref.read(consultationRepositoryProvider).end(widget.consultation.id);
    ref.invalidate(consultationProvider(widget.consultation.id));
  }

  Future<void> _switchToAudio() async {
    // Stop publishing video first, then record the mode change. Doing it in
    // this order means the bandwidth drops immediately, which is the entire
    // point of the fallback.
    await ref.read(callControllerProvider.notifier).setCameraEnabled(false);
    await ref
        .read(consultationRepositoryProvider)
        .switchToAudio(widget.consultation.id);
    if (mounted) setState(() => _cameraOff = true);
    ref.invalidate(consultationProvider(widget.consultation.id));
  }

  Future<void> _send() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    _messageCtrl.clear();
    // Sent over the vendor data channel AND relayed to our database: retention
    // of the consultation record is our obligation, not the vendor's.
    await ref.read(callControllerProvider.notifier).sendMessage(text);
    await ref
        .read(consultationRepositoryProvider)
        .sendMessage(widget.consultation.id, text);
    ref.invalidate(consultationProvider(widget.consultation.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.consultation;
    final call = ref.watch(callControllerProvider);
    final quality =
        ref.watch(networkQualityProvider(c.id)).value ?? NetworkQuality.good;

    return Stack(
      children: [
        // Remote video fills the screen; falls back to an avatar when the
        // other side has no video track (audio call, camera off, or still
        // connecting).
        _RemoteVideo(consultation: c, call: call),

        // Local preview, picture-in-picture.
        if (!_cameraOff && c.mode == ConsultationMode.video)
          Positioned(
            right: 12,
            top: 96,
            width: 100,
            height: 140,
            child: _LocalPreview(call: call),
          ),

        if (call.isReconnecting)
          const Positioned(
            left: 0,
            right: 0,
            top: 64,
            child: _ReconnectingBanner(),
          ),

        SafeArea(
          child: Column(
            children: [
              _TopBar(consultation: c, quality: quality),
              // Poor connection is common on Indian mobile networks, so the
              // audio fallback is offered in-place rather than left for the
              // user to discover after the call fails.
              if (quality == NetworkQuality.poor &&
                  c.mode != ConsultationMode.audio)
                _AudioFallbackBanner(onSwitch: _switchToAudio),
              const Spacer(),
              if (_chatOpen)
                _ChatPanel(
                  consultation: c,
                  controller: _messageCtrl,
                  onSend: _send,
                  onClose: () => setState(() => _chatOpen = false),
                ),
              _ControlBar(
                muted: _muted,
                cameraOff: _cameraOff,
                isVideo: c.mode == ConsultationMode.video,
                unreadChat: c.messages.length,
                onToggleMute: _toggleMute,
                onToggleCamera: _toggleCamera,
                onSwitchCamera: () =>
                    ref.read(callControllerProvider.notifier).switchCamera(),
                onToggleChat: () => setState(() => _chatOpen = !_chatOpen),
                onEnd: _end,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.consultation, required this.quality});

  final Consultation consultation;
  final NetworkQuality quality;

  @override
  Widget build(BuildContext context) {
    final c = consultation;
    final duration = c.duration ?? Duration.zero;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black.withValues(alpha: 0.45),
      child: Row(
        children: [
          // Identity and registration number stay visible for the whole call,
          // as the Telemedicine Practice Guidelines require.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.doctor.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                Text(
                  'Reg. ${c.doctor.registrationNumber}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Fmt.countdown(duration),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              Row(
                children: [
                  Icon(
                    switch (quality) {
                      NetworkQuality.good => Icons.signal_cellular_alt,
                      NetworkQuality.fair => Icons.signal_cellular_alt_2_bar,
                      NetworkQuality.poor => Icons.signal_cellular_alt_1_bar,
                    },
                    size: 13,
                    color: switch (quality) {
                      NetworkQuality.good => Colors.greenAccent,
                      NetworkQuality.fair => Colors.amberAccent,
                      NetworkQuality.poor => Colors.redAccent,
                    },
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Not recorded',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AudioFallbackBanner extends StatelessWidget {
  const _AudioFallbackBanner({required this.onSwitch});

  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade800,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.signal_wifi_statusbar_connected_no_internet_4,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Your connection is weak. Switching to audio usually helps.',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onSwitch,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(context.l10n.consultSwitch),
          ),
        ],
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.consultation,
    required this.controller,
    required this.onSend,
    required this.onClose,
  });

  final Consultation consultation;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 300,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(context.l10n.consultationChat),
            subtitle: Text(context.l10n.consultKeptWithRecord),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: consultation.messages.isEmpty
                ? Center(child: Text(context.l10n.consultNoMessages))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: consultation.messages.length,
                    itemBuilder: (_, i) {
                      final m = consultation.messages[i];
                      return Align(
                        alignment: m.isFromMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: m.isFromMe
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(m.body),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    // Consultation chat is clinical by definition. See
                    // `edit_profile_screen.dart`.
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: context.l10n.consultationChatHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: onSend),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.muted,
    required this.cameraOff,
    required this.isVideo,
    required this.unreadChat,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onToggleChat,
    required this.onEnd,
  });

  final bool muted;
  final bool cameraOff;
  final bool isVideo;
  final int unreadChat;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleChat;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CircleButton(
            icon: muted ? Icons.mic_off : Icons.mic,
            onPressed: onToggleMute,
            active: muted,
          ),
          if (isVideo)
            _CircleButton(
              icon: cameraOff ? Icons.videocam_off : Icons.videocam,
              onPressed: onToggleCamera,
              active: cameraOff,
            ),
          if (isVideo && !cameraOff)
            _CircleButton(
              icon: Icons.cameraswitch_outlined,
              onPressed: onSwitchCamera,
            ),
          Badge(
            isLabelVisible: unreadChat > 0,
            label: Text('$unreadChat'),
            child: _CircleButton(
              icon: Icons.chat_bubble_outline,
              onPressed: onToggleChat,
            ),
          ),
          _CircleButton(
            icon: Icons.call_end,
            onPressed: onEnd,
            background: Colors.red,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.background,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background ??
          (active ? Colors.white : Colors.white.withValues(alpha: 0.2)),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(
            icon,
            color: background != null
                ? Colors.white
                : (active ? Colors.black87 : Colors.white),
          ),
        ),
      ),
    );
  }
}

class _EndedView extends StatelessWidget {
  const _EndedView({required this.consultation});

  final Consultation consultation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = consultation;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text(context.l10n.consultationEnded,
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (c.duration != null)
              Text('Lasted ${Fmt.duration(c.duration!)}',
                  style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              'No recording was made. Your doctor’s notes and any '
              'prescription are saved to your records.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.actionDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Remote participant's video, or a dignified fallback.
class _RemoteVideo extends ConsumerWidget {
  const _RemoteVideo({required this.consultation, required this.call});

  final Consultation consultation;
  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final remote = call.remote;
    final view = remote == null
        ? null
        : ref.read(telehealthProviderProvider).videoViewFor(remote);

    if (view != null && !(remote?.isVideoMuted ?? true)) {
      return Positioned.fill(child: view);
    }

    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 48,
              child: Text(
                consultation.doctor.name.split(' ').last[0],
                style: theme.textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              consultation.doctor.name,
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            Text(
              consultation.mode == ConsultationMode.audio
                  ? 'Audio consultation'
                  : call.isConnected
                      ? 'Camera is off'
                      : 'Connecting',
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

/// Local camera preview, shown picture-in-picture.
class _LocalPreview extends ConsumerWidget {
  const _LocalPreview({required this.call});

  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = call.local;
    final view = local == null
        ? null
        : ref.read(telehealthProviderProvider).videoViewFor(local);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: Colors.black54,
        child: view ??
            const Center(
              child: Icon(Icons.videocam_off, color: Colors.white54, size: 20),
            ),
      ),
    );
  }
}

/// Shown while the SDK re-establishes a dropped connection.
///
/// Indian mobile connections drop often enough that silence here reads as a
/// frozen app, and the user hangs up on a consultation that was about to
/// recover.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Reconnecting',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
