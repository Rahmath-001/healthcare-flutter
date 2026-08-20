import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/session/session.dart';
import 'package:healthcare_mobile/core/session/user_role.dart';

void main() {
  group('Session.fromJson', () {
    test('maps the wire format the API returns', () {
      final s = Session.fromJson(const {
        'userId': 'u-1',
        'sessionId': 'sid-1',
        'accessToken': 'jwt',
        'expiresIn': 900,
        'role': 'PROVIDER',
        'status': 'ACTIVE',
        'providerStatus': 'APPROVED',
        'scopes': ['profile:read', 'prescription:write'],
        'permissionVersion': 7,
        'displayName': 'Dr Sharma',
        'phone': '+919876543210',
      });

      expect(s.userId, 'u-1');
      expect(s.role, UserRole.provider);
      expect(s.accountStatus, AccountStatus.active);
      expect(s.providerStatus, ProviderStatus.approved);
      expect(s.permissionVersion, 7);
      expect(s.hasScope('prescription:write'), isTrue);
      expect(s.isAccessTokenExpired, isFalse);
    });

    test('unknown role degrades to unassigned rather than throwing', () {
      // A token for a role this build predates must not crash the app.
      expect(UserRole.fromWire('DISTRICT_COORDINATOR'), UserRole.unassigned);
      expect(UserRole.fromWire(null), UserRole.unassigned);
    });

    test('unknown provider status degrades to notApplicable', () {
      expect(
          ProviderStatus.fromWire('PENDING_NMC'), ProviderStatus.notApplicable);
    });
  });

  group('scopes', () {
    Session withScopes(Set<String> scopes) => Session(
          userId: 'u',
          sessionId: 's',
          accessToken: 't',
          accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
          role: UserRole.patient,
          accountStatus: AccountStatus.active,
          providerStatus: ProviderStatus.notApplicable,
          scopes: scopes,
          permissionVersion: 1,
        );

    test('exact scope matches', () {
      expect(withScopes({'appointment:create'}).hasScope('appointment:create'),
          isTrue);
      expect(withScopes({'appointment:create'}).hasScope('records:read_own'),
          isFalse);
    });

    test('admin wildcard grants everything', () {
      final admin = withScopes({'*:*'});
      expect(admin.hasScope('records:read_granted'), isTrue);
      expect(admin.hasScope('anything:at:all'), isTrue);
    });

    test('a partial wildcard does NOT grant unrelated scopes', () {
      // Guards against a sloppy prefix match creeping in later.
      expect(withScopes({'records:*'}).hasScope('prescription:write'), isFalse);
    });
  });

  group('token expiry', () {
    Session expiringAt(DateTime at) => Session(
          userId: 'u',
          sessionId: 's',
          accessToken: 't',
          accessTokenExpiresAt: at,
          role: UserRole.patient,
          accountStatus: AccountStatus.active,
          providerStatus: ProviderStatus.notApplicable,
          scopes: const {},
          permissionVersion: 1,
        );

    test('treats a token as expired shortly before it actually expires', () {
      // The 30s skew stops a request being sent with a token that dies in
      // flight, which would surface as a spurious 401.
      expect(
        expiringAt(DateTime.now().add(const Duration(seconds: 10)))
            .isAccessTokenExpired,
        isTrue,
      );
      expect(
        expiringAt(DateTime.now().add(const Duration(minutes: 5)))
            .isAccessTokenExpired,
        isFalse,
      );
    });
  });

  group('usability', () {
    Session withStatus(AccountStatus status) => Session(
          userId: 'u',
          sessionId: 's',
          accessToken: 't',
          accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
          role: UserRole.patient,
          accountStatus: status,
          providerStatus: ProviderStatus.notApplicable,
          scopes: const {},
          permissionVersion: 1,
        );

    test('only an active account is usable', () {
      expect(withStatus(AccountStatus.active).isUsable, isTrue);
      expect(withStatus(AccountStatus.suspended).isUsable, isFalse);
      expect(withStatus(AccountStatus.deactivated).isUsable, isFalse);
      expect(withStatus(AccountStatus.pending).isUsable, isFalse);
    });
  });

  group('provider access', () {
    test('only APPROVED has full provider access', () {
      for (final status in ProviderStatus.values) {
        expect(
          status.hasFullProviderAccess,
          status == ProviderStatus.approved,
          reason: status.name,
        );
      }
    });
  });

  group('role support', () {
    test('only patient and provider are supported on mobile', () {
      expect(UserRole.patient.isSupportedOnMobile, isTrue);
      expect(UserRole.provider.isSupportedOnMobile, isTrue);
      for (final role in [
        UserRole.supervisor,
        UserRole.supportL1,
        UserRole.supportL2,
        UserRole.admin,
        UserRole.unassigned,
      ]) {
        expect(role.isSupportedOnMobile, isFalse, reason: role.name);
      }
    });
  });
}
