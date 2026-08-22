import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feature_providers.dart';
import '../../../core/providers.dart';
import '../data/push_service.dart';
import '../domain/notification.dart';
import 'notifications_controller.dart';
import 'notifications_screen.dart';

final pushServiceProvider = Provider<PushService>((ref) => PushService());

/// Keeps the device's push token attached to whoever is signed in, and routes
/// taps to the right screen.
///
/// Mounted once, above the router. Three things have to happen in the right
/// order and none of them belong to a screen:
///
///  1. **Register on sign-in, unregister on sign-out.** Phones are commonly
///     shared here. Without the unregister, the next person to sign in keeps
///     receiving the previous user's appointment and prescription
///     notifications — on this app that is a disclosure, not an annoyance.
///  2. **Re-register on rotation.** FCM rotates tokens on reinstall and
///     restore. A token registered once and never again stops matching the
///     device, and the symptom is notifications quietly ceasing with nothing
///     in any log.
///  3. **Handle the cold-start tap separately.** A terminated app launched by
///     a notification never passes through `onMessageOpenedApp`; missing
///     `getInitialMessage` is why "the tap opens the app but not the thing" is
///     such a common bug.
class PushCoordinator extends ConsumerStatefulWidget {
  const PushCoordinator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushCoordinator> createState() => _PushCoordinatorState();
}

class _PushCoordinatorState extends ConsumerState<PushCoordinator> {
  final _subscriptions = <StreamSubscription<dynamic>>[];
  String? _registeredFor;
  bool _listening = false;

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  void _startListening() {
    if (_listening) return;
    _listening = true;

    final push = ref.read(pushServiceProvider);
    if (!push.isSupported) return;

    _subscriptions.add(push.tokenRefreshes.listen((token) {
      if (_registeredFor == null) return;
      unawaited(_register(token));
    }));

    _subscriptions.add(push.foregroundMessages.listen((_) {
      // The OS does not draw a foreground notification on Android, so the app
      // has to react itself. Refreshing the list is what moves the badge.
      ref.invalidate(notificationsProvider);
    }));

    _subscriptions.add(push.openedFromBackground.listen(_openFromMessage));

    unawaited(push.initialMessage().then((message) {
      if (message != null) _openFromMessage(message);
    }));
  }

  Future<void> _register(String token) async {
    try {
      await ref.read(notificationRepositoryProvider).registerDevice(
            token: token,
            platform: defaultTargetPlatform.name,
          );
    } catch (e) {
      // A failed registration means no notifications, which is bad but not
      // worth interrupting a sign-in over. The next token refresh or app
      // launch retries.
      if (kDebugMode) debugPrint('Device registration failed: $e');
    }
  }

  void _openFromMessage(RemoteMessage message) {
    final payload = payloadOf(message);
    if (payload.kind == null) return;

    // Rebuilt into a domain object so the tap goes through exactly the same
    // routing function the notification centre uses. Two implementations of
    // "where does this kind lead" is how a push and an in-app tap end up in
    // different places.
    final target = routeForNotification(
      AppNotification(
        id: message.messageId ?? '',
        kind: NotificationKind.fromWire(payload.kind),
        title: '',
        body: '',
        createdAt: DateTime.now(),
        targetId: payload.targetId,
      ),
    );
    if (target == null || !mounted) return;

    // Deferred to the next frame: a cold start delivers the initial message
    // before the router has finished its first build, and pushing into a
    // router that has not resolved its redirect yet lands the user on a screen
    // the session may not even allow.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GoRouter.of(context).push(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    final userId = session?.userId;

    if (userId != _registeredFor) {
      final previous = _registeredFor;
      _registeredFor = userId;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final push = ref.read(pushServiceProvider);

        if (userId == null) {
          if (previous != null) {
            // Detach before the next person signs in on this phone.
            try {
              await ref.read(notificationRepositoryProvider).unregisterDevice();
            } catch (_) {
              // Best effort. A failed unregister is retried by the next
              // successful sign-in, which overwrites the mapping anyway.
            }
          }
          return;
        }

        _startListening();

        // Only registers a token that already exists. Asking for permission
        // here would put the system prompt in front of someone who has just
        // signed in and has no idea what it is for — onboarding asks, with an
        // explanation.
        final permission = await push.currentPermission();
        if (permission != PushPermission.granted) return;

        final token = await push.token();
        if (token != null) await _register(token);
      });
    }

    return widget.child;
  }
}
