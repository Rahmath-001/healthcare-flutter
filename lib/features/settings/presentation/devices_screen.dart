import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/feature_providers.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/haptics.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/skeleton.dart';
import '../domain/signed_in_device.dart';

final signedInDevicesProvider =
    FutureProvider<List<SignedInDevice>>((ref) async {
  return ref.watch(deviceSessionRepositoryProvider).list();
});

/// Where this account is signed in, and how to end a session.
///
/// The remedy that would otherwise not exist. Identity here is Google, Apple
/// or a phone OTP — there is no password to change, so "sign out everywhere"
/// is the only lever a person has when they have handed their phone to
/// somebody in a waiting room or signed in on a shared machine.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(signedInDevicesProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.devicesTitle)),
      body: AsyncView<List<SignedInDevice>>(
        value: devices,
        onRetry: () => ref.invalidate(signedInDevicesProvider),
        skeleton: const SkeletonList(rows: 2),
        data: (list) => _DeviceList(devices: list),
      ),
    );
  }
}

class _DeviceList extends ConsumerWidget {
  const _DeviceList({required this.devices});

  final List<SignedInDevice> devices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final others = devices.where((d) => !d.isCurrent).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        Insets.md,
        Insets.gutter,
        Insets.xxl,
      ),
      children: [
        Text(l10n.devicesBody, style: theme.textTheme.bodySmall),
        const SizedBox(height: Insets.lg),

        for (var i = 0; i < devices.length; i++)
          FadeSlideIn(
            key: ValueKey(devices[i].id),
            index: i,
            child: _DeviceTile(device: devices[i]),
          ),

        if (others > 0) ...[
          const SizedBox(height: Insets.xl),
          // The button people actually want: "get everyone else out" without
          // having to work out which row is their own phone.
          OutlinedButton.icon(
            onPressed: () => _revokeOthers(context, ref, others),
            icon: const Icon(Icons.logout, size: 18),
            label: Text(l10n.devicesSignOutOthers(others)),
          ),
        ],

        const SizedBox(height: Insets.lg),
        // Says what is not collected, because a device list is exactly where
        // people expect to see a location and are entitled to know why they
        // do not.
        Text(l10n.devicesPrivacyNote, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Future<void> _revokeOthers(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.devicesSignOutOthers(count)),
        content: Text(l10n.devicesSignOutOthersBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.devicesSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final n = await ref.read(deviceSessionRepositoryProvider).revokeOthers();
      ref.invalidate(signedInDevicesProvider);
      Haptics.success();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.devicesSignedOutCount(n))),
      );
    } on Failure catch (e) {
      Haptics.warning();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _DeviceTile extends ConsumerStatefulWidget {
  const _DeviceTile({required this.device});

  final SignedInDevice device;

  @override
  ConsumerState<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends ConsumerState<_DeviceTile> {
  bool _busy = false;

  Future<void> _revoke() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final device = widget.device;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.devicesSignOut),
        // Ending your own session is signing out, and it should say so rather
        // than leaving somebody to discover it.
        content: Text(device.isCurrent
            ? l10n.devicesSignOutCurrentBody
            : l10n.devicesSignOutOneBody(device.platformLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.devicesSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(deviceSessionRepositoryProvider).revoke(device.id);
      if (device.isCurrent) {
        // No point refreshing a list this device is no longer entitled to
        // read. The session controller takes it from here.
        await ref.read(sessionControllerProvider.notifier).signOut();
        return;
      }
      ref.invalidate(signedInDevicesProvider);
      Haptics.success();
    } on Failure catch (e) {
      Haptics.warning();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = context.tones;
    final l10n = context.l10n;
    final d = widget.device;
    final stale = d.staleAt(DateTime.now());

    final icon = switch (d.platform.toLowerCase()) {
      'android' => Icons.phone_android,
      'ios' => Icons.phone_iphone,
      'web' => Icons.language,
      _ => Icons.devices_other,
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: d.isCurrent
            ? tones.successContainer
            : theme.colorScheme.surfaceContainerHigh,
        child: Icon(
          icon,
          size: 20,
          color: d.isCurrent ? tones.success : theme.colorScheme.onSurface,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(d.platformLabel, style: theme.textTheme.titleSmall),
          ),
          if (d.isCurrent) ...[
            const SizedBox(width: Insets.sm),
            Text(
              l10n.devicesThisDevice,
              style: theme.textTheme.labelSmall?.copyWith(color: tones.success),
            ),
          ],
        ],
      ),
      subtitle: Text(
        d.isCurrent
            ? l10n.devicesSignedInOn(Fmt.date(d.createdAt))
            : l10n.devicesLastUsed(Fmt.relative(d.lastSeenAt)),
        style: theme.textTheme.bodySmall?.copyWith(
          // A nudge, not a verdict: an old session is usually a spare tablet.
          color: stale ? tones.warning : null,
        ),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : IconButton(
              tooltip: l10n.devicesSignOut,
              icon: const Icon(Icons.logout),
              onPressed: _revoke,
            ),
    );
  }
}
