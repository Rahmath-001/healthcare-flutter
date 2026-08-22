import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// The device's relationship with FCM.
///
/// Everything vendor-specific lives here. Above this line the app deals in
/// [PushPermission] and a token string, so swapping FCM for another provider —
/// or running with none at all on sample data — touches one file.
///
/// ## What this does not do
///
/// It does not decide *whether* a notification should have been sent. That is
/// `NotificationPreferences`, evaluated server-side, because a client-side
/// filter only stops the app from rendering something the phone has already
/// buzzed about and put on the lock screen.
enum PushPermission { granted, denied, notDetermined, unsupported }

class PushService {
  PushService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  /// firebase_messaging ships Android, iOS, macOS and web — but the web build
  /// additionally needs a `firebase-messaging-sw.js` service worker and a VAPID
  /// key, neither of which this project has. Rather than fail at runtime with a
  /// registration error nobody can act on, web reports `unsupported` and the UI
  /// says notifications are unavailable there.
  bool get isSupported => !kIsWeb;

  /// Asks the OS, and reports what it said.
  ///
  /// On Android 13+ and on iOS this shows the system prompt exactly once ever;
  /// a second call returns the standing answer without prompting. That is why
  /// the onboarding screen asks rather than a settings toggle: the one chance
  /// to ask should come with an explanation of what will be sent.
  Future<PushPermission> requestPermission() async {
    if (!isSupported) return PushPermission.unsupported;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      // Never. A provisional authorization delivers quietly without asking,
      // which is defensible for a newsletter and not for an app whose
      // notifications are the only warning that a consultation moved.
      provisional: false,
    );

    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional =>
        PushPermission.granted,
      AuthorizationStatus.denied => PushPermission.denied,
      AuthorizationStatus.notDetermined => PushPermission.notDetermined,
    };
  }

  Future<PushPermission> currentPermission() async {
    if (!isSupported) return PushPermission.unsupported;
    final settings = await _messaging.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional =>
        PushPermission.granted,
      AuthorizationStatus.denied => PushPermission.denied,
      AuthorizationStatus.notDetermined => PushPermission.notDetermined,
    };
  }

  /// This install's token, or null if there is none to have.
  ///
  /// Null is normal rather than exceptional: on iOS the token is unavailable
  /// until APNs has registered the device, which can lag the permission grant
  /// by a second or two, and on a simulator without a push profile it never
  /// arrives at all. Callers register again from [tokenRefreshes].
  Future<String?> token() async {
    if (!isSupported) return null;
    try {
      return await _messaging.getToken();
    } catch (e) {
      // A missing APNs profile throws here. It is a configuration problem on
      // the developer's machine, not something the patient can act on, so it
      // degrades to "no push" rather than to a crash on first launch.
      if (kDebugMode) debugPrint('FCM token unavailable: $e');
      return null;
    }
  }

  /// Fires whenever FCM rotates the token.
  ///
  /// It rotates on reinstall, on restore to a new device, and occasionally on
  /// its own. A token registered once at first launch and never again is a
  /// token that silently stops matching the device, which presents as
  /// notifications simply ceasing for that user with nothing in any log.
  Stream<String> get tokenRefreshes =>
      isSupported ? _messaging.onTokenRefresh : const Stream<String>.empty();

  /// Messages arriving while the app is open and in front of the user.
  ///
  /// The OS does not display these on Android, so the app is responsible for
  /// reacting — here, by refreshing the notification list and the badge.
  Stream<RemoteMessage> get foregroundMessages =>
      isSupported ? FirebaseMessaging.onMessage : const Stream.empty();

  /// A notification the user tapped, which brought the app to the foreground.
  Stream<RemoteMessage> get openedFromBackground =>
      isSupported ? FirebaseMessaging.onMessageOpenedApp : const Stream.empty();

  /// The notification that launched a terminated app, if that is how it
  /// started.
  ///
  /// Separate from [openedFromBackground] because a cold start does not go
  /// through that stream at all — missing this is why "tapping the
  /// notification opens the app but not the thing" is such a common bug.
  Future<RemoteMessage?> initialMessage() async {
    if (!isSupported) return null;
    return _messaging.getInitialMessage();
  }
}

/// Reads our routing hint out of an FCM payload.
///
/// The server puts `kind` and `targetId` in the data block rather than relying
/// on the notification block, because the data block is delivered identically
/// whether the app is foreground, background or terminated.
({String? kind, String? targetId}) payloadOf(RemoteMessage message) => (
      kind: message.data['kind'] as String?,
      targetId: message.data['targetId'] as String?,
    );
