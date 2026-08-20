import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/admin/admin_app.dart';
import 'package:healthcare_mobile/admin/router/admin_router.dart';
import 'package:healthcare_mobile/core/session/session.dart';
import 'package:healthcare_mobile/core/session/user_role.dart';

/// The operator console's front door.
///
/// This is the complement of `router_redirect_test.dart`: that one proves a
/// patient cannot reach a provider's screens, this one proves neither can reach
/// a reviewer's. Both are client-side conveniences over a server-side control —
/// but a console that renders a review queue to the wrong person, even briefly,
/// is a disclosure regardless of what the API would have refused.
Session session({
  required UserRole role,
  AccountStatus status = AccountStatus.active,
  Set<String> scopes = const {},
}) {
  return Session(
    userId: 'u1',
    sessionId: 's1',
    accessToken: 'token',
    accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
    role: role,
    accountStatus: status,
    providerStatus: ProviderStatus.notApplicable,
    scopes: scopes,
    permissionVersion: 1,
  );
}

String? redirect({
  required String location,
  Session? current,
  bool loading = false,
}) =>
    resolveAdminRedirect(
      location: location,
      sessionLoading: loading,
      session: current,
    );

void main() {
  group('resolveAdminRedirect', () {
    test('waits rather than bouncing while the session is still loading', () {
      // Redirecting to sign-in here would flash the login page on every reload
      // for an operator who is already signed in.
      expect(
        redirect(location: AdminRoutes.queue, loading: true),
        isNull,
      );
    });

    test('sends a signed-out visitor to sign-in', () {
      expect(redirect(location: AdminRoutes.queue), AdminRoutes.signIn);
      expect(redirect(location: AdminRoutes.users), AdminRoutes.signIn);
      expect(redirect(location: AdminRoutes.signIn), isNull);
    });

    test('lets staff roles through', () {
      for (final role in [
        UserRole.supervisor,
        UserRole.admin,
        UserRole.supportL1,
        UserRole.supportL2,
      ]) {
        expect(
          redirect(location: AdminRoutes.queue, current: session(role: role)),
          isNull,
          reason: role.name,
        );
      }
    });

    test('refuses patients and providers', () {
      // They have their own app, and their token carries none of the scopes
      // anything here needs.
      for (final role in [
        UserRole.patient,
        UserRole.provider,
        UserRole.unassigned,
      ]) {
        expect(
          redirect(location: AdminRoutes.queue, current: session(role: role)),
          AdminRoutes.signIn,
          reason: role.name,
        );
      }
    });

    test('refuses a suspended or deactivated operator', () {
      for (final status in [
        AccountStatus.suspended,
        AccountStatus.deactivated,
      ]) {
        expect(
          redirect(
            location: AdminRoutes.queue,
            current: session(role: UserRole.admin, status: status),
          ),
          AdminRoutes.signIn,
          reason: status.name,
        );
      }
    });

    test('moves a signed-in operator off the sign-in page', () {
      expect(
        redirect(
          location: AdminRoutes.signIn,
          current: session(role: UserRole.supervisor),
        ),
        AdminRoutes.queue,
      );
    });

    test('leaves an operator alone on every console route', () {
      final s = session(role: UserRole.admin);
      for (final route in [
        AdminRoutes.queue,
        AdminRoutes.users,
        AdminRoutes.ratings,
        AdminRoutes.tickets,
        AdminRoutes.provider('u9'),
        AdminRoutes.ticket('t9'),
      ]) {
        expect(redirect(location: route, current: s), isNull, reason: route);
      }
    });
  });

  group('isOperator', () {
    test('is exactly the complement of the mobile app', () {
      // Every role belongs to precisely one of the two clients. A role in
      // neither would be an account that can sign in and reach nothing.
      for (final role in UserRole.values) {
        final onMobile = role.isSupportedOnMobile;
        final onConsole = isOperator(session(role: role));
        if (role == UserRole.unassigned) {
          // The exception, and deliberately so: a brand-new account has no
          // client until the API assigns it a role.
          expect(onMobile, isFalse);
          expect(onConsole, isFalse);
        } else {
          expect(onMobile == onConsole, isFalse, reason: role.name);
        }
      }
    });

    test('is false without a session', () {
      expect(isOperator(null), isFalse);
    });
  });

  group('OperatorAccess', () {
    test('reads the same scopes the API enforces', () {
      const supervisor = {
        'provider:review',
        'provider:approve',
        'user:suspend',
      };
      expect(supervisor.canReviewProviders, isTrue);
      expect(supervisor.canDecideProviders, isTrue);
      expect(supervisor.canSuspendAccounts, isTrue);
      // Role assignment is admin-only — the single most dangerous call.
      expect(supervisor.canAssignRoles, isFalse);
      expect(supervisor.canReadTickets, isFalse);
    });

    test('treats the admin wildcard as everything', () {
      const admin = {'*:*'};
      expect(admin.canAssignRoles, isTrue);
      expect(admin.canEscalateTickets, isTrue);
      expect(admin.canReviewProviders, isTrue);
    });

    test('grants nothing on an empty scope set', () {
      const none = <String>{};
      expect(none.canReviewProviders, isFalse);
      expect(none.canSuspendAccounts, isFalse);
      expect(none.canAssignRoles, isFalse);
    });
  });
}
