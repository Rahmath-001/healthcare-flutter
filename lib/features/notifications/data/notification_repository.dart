import '../../../core/fixtures/fixture_backend.dart';
import '../../../core/network/api_client.dart';
import '../domain/notification.dart';

abstract class NotificationRepository {
  /// The notification centre, newest first.
  Future<List<AppNotification>> list();

  Future<void> markRead(String id);
  Future<void> markAllRead();

  Future<NotificationPreferences> preferences();
  Future<void> updatePreferences(NotificationPreferences preferences);

  /// Associates this install's push token with the signed-in user.
  ///
  /// Called after every sign-in and on every token rotation, not once at
  /// install: FCM rotates tokens on reinstall, restore and occasionally on its
  /// own, and a stale token is a notification delivered to nobody.
  Future<void> registerDevice({
    required String token,
    required String platform,
  });

  /// Detaches this install's token, on sign-out.
  ///
  /// Without it, the next person to sign in on a shared phone inherits the
  /// previous user's notifications — which on this app means their appointments
  /// and their prescriptions.
  Future<void> unregisterDevice();
}

class FixtureNotificationRepository implements NotificationRepository {
  FixtureNotificationRepository({
    this.latency = const Duration(milliseconds: 250),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<List<AppNotification>> list() async {
    await Future<void>.delayed(latency);
    return _backend.notifications();
  }

  @override
  Future<void> markRead(String id) async {
    await Future<void>.delayed(latency);
    _backend.markNotificationRead(id);
  }

  @override
  Future<void> markAllRead() async {
    await Future<void>.delayed(latency);
    _backend.markAllNotificationsRead();
  }

  @override
  Future<NotificationPreferences> preferences() async {
    await Future<void>.delayed(latency);
    return _backend.notificationPreferences();
  }

  @override
  Future<void> updatePreferences(NotificationPreferences preferences) async {
    await Future<void>.delayed(latency);
    _backend.setNotificationPreferences(preferences);
  }

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
  }) async {
    await Future<void>.delayed(latency);
    // Recorded rather than ignored, so `fixture_backend_test` can assert the
    // registration actually happened. Sample data has no push service behind
    // it and nothing is ever delivered.
    _backend.registerDevice(token);
  }

  @override
  Future<void> unregisterDevice() async {
    await Future<void>.delayed(latency);
    _backend.unregisterDevice();
  }
}

class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AppNotification>> list() async {
    final json = await _api.get<List<dynamic>>('/v1/notifications');
    return json
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> markRead(String id) =>
      _api.post<Map<String, dynamic>>('/v1/notifications/$id/read');

  @override
  Future<void> markAllRead() =>
      _api.post<Map<String, dynamic>>('/v1/notifications/read-all');

  @override
  Future<NotificationPreferences> preferences() async {
    final json =
        await _api.get<Map<String, dynamic>>('/v1/notifications/preferences');
    return NotificationPreferences.fromJson(json);
  }

  @override
  Future<void> updatePreferences(NotificationPreferences preferences) =>
      _api.put<Map<String, dynamic>>(
        '/v1/notifications/preferences',
        body: preferences.toJson(),
      );

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
  }) =>
      _api.post<Map<String, dynamic>>(
        '/v1/notifications/devices',
        body: {'token': token, 'platform': platform},
      );

  @override
  Future<void> unregisterDevice() =>
      _api.delete<Map<String, dynamic>>('/v1/notifications/devices');
}
