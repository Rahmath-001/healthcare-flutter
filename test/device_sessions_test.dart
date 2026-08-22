import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/fixtures/fixture_backend.dart';
import 'package:healthcare_mobile/features/notifications/data/notification_repository.dart';
import 'package:healthcare_mobile/features/notifications/domain/notification.dart';
import 'package:healthcare_mobile/features/settings/data/device_session_repository.dart';
import 'package:healthcare_mobile/features/settings/domain/signed_in_device.dart';

/// Signed-in devices.
///
/// The remedy that would otherwise not exist: identity here is Google, Apple
/// or an OTP, so there is no password to change when somebody else has a live
/// session on your account.
void main() {
  const fast = Duration.zero;

  setUp(FixtureBackend.resetShared);

  group('the list', () {
    test('puts the device in your hand first', () async {
      // The one row a person has to identify before deciding anything about
      // the others.
      final repo = FixtureDeviceSessionRepository(latency: fast);
      final devices = await repo.list();

      expect(devices.length, greaterThan(1));
      expect(devices.first.isCurrent, isTrue);
      expect(devices.where((d) => d.isCurrent).length, 1);
    });

    test('orders the rest by when they were last used', () async {
      final repo = FixtureDeviceSessionRepository(latency: fast);
      final others = (await repo.list()).where((d) => !d.isCurrent).toList();

      for (var i = 1; i < others.length; i++) {
        expect(
          others[i - 1].lastSeenAt.isAfter(others[i].lastSeenAt),
          isTrue,
          reason: 'newest first',
        );
      }
    });

    test('carries no location, because none is collected', () async {
      // A location history is more use to somebody reading an unlocked phone
      // than it is to its owner. The type has nowhere to put one.
      final repo = FixtureDeviceSessionRepository(latency: fast);
      final device = (await repo.list()).first;

      expect(device.platform, isNotEmpty);
      expect(device.appVersion, isNotEmpty);
      // Every field there is: no ip, no city, no hardware id.
      expect(
        SignedInDevice(
          id: device.id,
          platform: device.platform,
          appVersion: device.appVersion,
          createdAt: device.createdAt,
          lastSeenAt: device.lastSeenAt,
          isCurrent: device.isCurrent,
        ).id,
        device.id,
      );
    });

    test('a long-unused session is flagged, not condemned', () async {
      final repo = FixtureDeviceSessionRepository(latency: fast);
      final devices = await repo.list();
      final now = DateTime.now();

      expect(devices.any((d) => d.staleAt(now)), isTrue,
          reason: 'the seed carries one untouched for a month');
      expect(devices.first.staleAt(now), isFalse,
          reason: 'the current device is not stale');
    });
  });

  group('ending a session', () {
    test('removes it, and cannot be done twice', () async {
      final repo = FixtureDeviceSessionRepository(latency: fast);
      final target = (await repo.list()).firstWhere((d) => !d.isCurrent);

      await repo.revoke(target.id);
      expect((await repo.list()).any((d) => d.id == target.id), isFalse);

      await expectLater(
        repo.revoke(target.id),
        throwsA(
            isA<Failure>().having((f) => f.code, 'code', 'SESSION_NOT_FOUND')),
      );
    });

    test('signing out others keeps this device and only this device', () async {
      final repo = FixtureDeviceSessionRepository(latency: fast);
      final before = await repo.list();

      final revoked = await repo.revokeOthers();
      expect(revoked, before.length - 1);

      final after = await repo.list();
      expect(after.length, 1);
      expect(after.single.isCurrent, isTrue);
    });

    test('nothing to revoke is zero, not an error', () async {
      final repo = FixtureDeviceSessionRepository(latency: fast);
      await repo.revokeOthers();
      expect(await repo.revokeOthers(), 0);
    });

    test('the account is told, and cannot be told quietly', () async {
      // The button an attacker would also press. An account update is
      // mandatory and bypasses quiet hours by kind, so clearing somebody's
      // other devices cannot be done silently at 3am.
      final repo = FixtureDeviceSessionRepository(latency: fast);
      final notifications = FixtureNotificationRepository(latency: fast);
      final target = (await repo.list()).firstWhere((d) => !d.isCurrent);

      await repo.revoke(target.id);

      final told = (await notifications.list())
          .firstWhere((n) => n.kind == NotificationKind.accountUpdate);
      expect(told.kind.isMandatory, isTrue);
      expect(told.kind.bypassesQuietHours, isTrue);
    });
  });
}
