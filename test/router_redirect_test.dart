import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/router/app_router.dart';
import 'package:healthcare_mobile/core/router/routes.dart';
import 'package:healthcare_mobile/core/session/session.dart';
import 'package:healthcare_mobile/core/session/user_role.dart';

Session session({
  UserRole role = UserRole.patient,
  AccountStatus status = AccountStatus.active,
  ProviderStatus providerStatus = ProviderStatus.notApplicable,
}) =>
    Session(
      userId: 'u1',
      sessionId: 's1',
      accessToken: 'token',
      accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
      role: role,
      accountStatus: status,
      providerStatus: providerStatus,
      scopes: const {},
      permissionVersion: 1,
    );

String? redirect({
  required String location,
  bool loading = false,
  Session? current,
}) =>
    resolveRedirect(
      location: location,
      sessionLoading: loading,
      session: current,
    );

void main() {
  group('post-sign-in booking return', () {
    test('accepts only a patient booking path', () {
      expect(
        bookingReturnPath('/patient/doctors/d-ramesh/book'),
        '/patient/doctors/d-ramesh/book',
      );
    });

    test('rejects external and non-booking destinations', () {
      expect(bookingReturnPath('https://example.com'), isNull);
      expect(bookingReturnPath('/patient/records'), isNull);
    });
  });

  group('while the session is loading', () {
    test('holds on splash', () {
      expect(redirect(location: Routes.splash, loading: true), isNull);
    });

    test('sends every other route to splash', () {
      // Prevents flashing the login screen at a user who is in fact signed in.
      expect(
          redirect(location: Routes.patientHome, loading: true), Routes.splash);
      expect(redirect(location: Routes.login, loading: true), Routes.splash);
    });
  });

  group('signed out', () {
    test('auth routes are allowed', () {
      for (final route in [
        Routes.login,
        Routes.signup,
        Routes.phone,
        Routes.otp,
        Routes.consent,
        Routes.organisationRegistration,
      ]) {
        expect(redirect(location: route), isNull, reason: route);
      }
    });

    test('everything else goes to the public catalogue', () {
      expect(redirect(location: Routes.patientHome), Routes.landing);
      expect(redirect(location: Routes.providerToday), Routes.landing);
      // Signing out from either patient or provider settings must return to
      // the public doctor catalogue, not leave an empty authenticated shell.
      expect(redirect(location: Routes.settings), Routes.landing);
      expect(redirect(location: Routes.providerProfile), Routes.landing);
      expect(redirect(location: Routes.splash), Routes.landing);
    });

    test('allows the public hospital directory and details', () {
      expect(redirect(location: '/hospitals'), isNull);
      expect(redirect(location: '/hospitals/test-hospital'), isNull);
    });
  });

  group('account status', () {
    test('suspended accounts are blocked, not signed out', () {
      final s = session(status: AccountStatus.suspended);
      expect(
          redirect(location: Routes.patientHome, current: s), Routes.blocked);
      expect(redirect(location: Routes.blocked, current: s), isNull);
    });

    test('deactivated accounts are blocked', () {
      final s = session(status: AccountStatus.deactivated);
      expect(
          redirect(location: Routes.patientHome, current: s), Routes.blocked);
    });
  });

  group('staff roles have no mobile UI', () {
    for (final role in [
      UserRole.supervisor,
      UserRole.supportL1,
      UserRole.supportL2,
      UserRole.admin,
      UserRole.unassigned,
    ]) {
      test('${role.name} is routed to blocked', () {
        final s = session(role: role);
        expect(
            redirect(location: Routes.patientHome, current: s), Routes.blocked);
        expect(redirect(location: Routes.providerToday, current: s),
            Routes.blocked);
        expect(redirect(location: Routes.blocked, current: s), isNull);
      });
    }
  });

  group('patient', () {
    test('bypasses the retired onboarding journey', () {
      final s = session();
      expect(
        redirect(
            location: Routes.patientHome,
            current: s),
        isNull,
      );
      expect(
        redirect(
            location: Routes.onboardingPatient,
            current: s),
        Routes.patientHome,
      );
    });

    test('cannot sit on auth or splash while signed in', () {
      expect(redirect(location: Routes.login, current: session()),
          Routes.patientHome);
      expect(redirect(location: Routes.splash, current: session()),
          Routes.patientHome);
    });

    test('cannot enter the provider shell', () {
      // The core cross-role containment check.
      expect(redirect(location: Routes.providerToday, current: session()),
          Routes.patientHome);
      expect(redirect(location: Routes.providerPatients, current: session()),
          Routes.patientHome);
    });

    test('stays put on its own routes', () {
      for (final route in [
        Routes.patientHome,
        Routes.patientAppointments,
        Routes.patientRecords,
        Routes.patientProfile,
      ]) {
        expect(redirect(location: route, current: session()), isNull,
            reason: route);
      }
    });
  });

  group('provider', () {
    Session provider(ProviderStatus status) =>
        session(role: UserRole.provider, providerStatus: status);

    test('only APPROVED reaches the provider shell', () {
      for (final status in ProviderStatus.values) {
        final result =
            redirect(location: Routes.providerToday, current: provider(status));
        if (status == ProviderStatus.approved) {
          expect(result, isNull, reason: status.name);
        } else {
          expect(result, Routes.providerVerification, reason: status.name);
        }
      }
    });

    test('unverified provider is pinned to the verification screen', () {
      final s = provider(ProviderStatus.submitted);
      expect(
          redirect(location: Routes.providerVerification, current: s), isNull);
      expect(redirect(location: Routes.patientHome, current: s),
          Routes.providerVerification);
      expect(redirect(location: Routes.patientRecords, current: s),
          Routes.providerVerification);
    });

    test('unverified provider may reach credential capture and MFA', () {
      // Submitting credentials is the only action an unapproved provider has,
      // and both of its screens are nested under the verification path. An
      // exact-match redirect here made 716 lines of UI unreachable.
      for (final status in ProviderStatus.values) {
        if (status == ProviderStatus.approved) continue;
        final s = provider(status);
        expect(
            redirect(location: Routes.providerCredentials, current: s), isNull,
            reason: status.name);
        expect(redirect(location: Routes.providerMfa, current: s), isNull,
            reason: status.name);
      }
    });

    test('approved provider cannot enter the patient shell', () {
      final s = provider(ProviderStatus.approved);
      expect(redirect(location: Routes.patientHome, current: s),
          Routes.providerToday);
      expect(redirect(location: Routes.patientRecords, current: s),
          Routes.providerToday);
    });

    test('approved provider skips patient onboarding entirely', () {
      final s = provider(ProviderStatus.approved);
      expect(
        redirect(
            location: Routes.providerToday,
            current: s),
        isNull,
      );
    });

    test('stays put on its own routes', () {
      final s = provider(ProviderStatus.approved);
      for (final route in [
        Routes.providerToday,
        Routes.providerSchedule,
        Routes.providerPatients,
        Routes.providerProfile,
      ]) {
        expect(redirect(location: route, current: s), isNull, reason: route);
      }
    });
  });

  group('hospital', () {
    final hospital = session(role: UserRole.hospital);

    test('lands in and remains within its own portal', () {
      expect(redirect(location: Routes.hospitalHome, current: hospital), isNull);
      expect(redirect(location: Routes.landing, current: hospital), Routes.hospitalHome);
      expect(redirect(location: Routes.patientHome, current: hospital), Routes.hospitalHome);
      expect(redirect(location: Routes.providerToday, current: hospital), Routes.hospitalHome);
    });
  });
}
