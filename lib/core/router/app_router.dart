import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../observability/crash_reporting.dart';
import '../providers.dart';
import '../session/onboarding_controller.dart';
import '../session/session.dart';
import '../session/user_role.dart';
import 'app_routes_builder.dart';
import 'routes.dart';

/// Bridges Riverpod state changes into go_router's refresh mechanism.
///
/// go_router only re-evaluates `redirect` when its [Listenable] fires, so
/// without this a sign-in or a provider approval would not move the user.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(sessionControllerProvider, (_, __) => notifyListeners());
    ref.listen(onboardingControllerProvider, (_, __) => notifyListeners());
  }
}

final _routerRefreshProvider = Provider<_RouterRefresh>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  return refresh;
});

/// Decides where a given session belongs.
///
/// Pure and free of Flutter types so it can be unit-tested exhaustively — this
/// function is where the RBAC matrix turns into navigation, and getting it
/// wrong means showing a patient a provider's screen.
@visibleForTesting
String? resolveRedirect({
  required String location,
  required bool sessionLoading,
  required Session? session,
  required bool onboardingComplete,
}) {
  final isAuthRoute = location.startsWith('/auth');
  final isSplash = location == Routes.splash;

  // Still restoring a session from the stored refresh token.
  if (sessionLoading) return isSplash ? null : Routes.splash;

  if (session == null) {
    // The catalogue is intentionally public: the first client-approved
    // screen lets someone browse doctors before deciding to register.
    return isAuthRoute || location == Routes.landing || location.startsWith('/doctors')
        ? null
        : Routes.landing;
  }

  // Suspended/deactivated accounts get a terminal screen rather than a silent
  // sign-out, so they can be told why and reach support.
  if (!session.isUsable) {
    return location == Routes.blocked ? null : Routes.blocked;
  }

  // Supervisor, support and admin have no mobile UI. Their tokens are valid;
  // this app simply is not their client.
  if (!session.role.isSupportedOnMobile) {
    return location == Routes.blocked ? null : Routes.blocked;
  }

  switch (session.role) {
    case UserRole.patient:
      if (!onboardingComplete) {
        return location == Routes.onboardingPatient
            ? null
            : Routes.onboardingPatient;
      }
      // A signed-in patient has no business on auth, splash or onboarding.
      if (isAuthRoute || isSplash || location.startsWith('/onboarding')) {
        return Routes.patientHome;
      }
      // Never let a patient land in the provider shell.
      if (location.startsWith('/provider')) return Routes.patientHome;
      return null;

    case UserRole.provider:
      // Everything except APPROVED sees only the verification screen. This is
      // the RBAC matrix rendered as routing: an unverified provider may read
      // their own profile and submit credentials, and nothing else.
      if (!session.providerStatus.hasFullProviderAccess) {
        // The verification screen and everything nested under it — credential
        // capture and MFA enrolment — stay reachable. Submitting credentials is
        // the one thing an unapproved provider is allowed to do, so an exact
        // match here would strand them on a screen whose only action is a push
        // to a child route.
        return location.startsWith(Routes.providerVerification)
            ? null
            : Routes.providerVerification;
      }
      if (isAuthRoute || isSplash || location.startsWith('/onboarding')) {
        return Routes.providerToday;
      }
      if (location.startsWith('/patient')) return Routes.providerToday;
      return null;

    case UserRole.supervisor:
    case UserRole.supportL1:
    case UserRole.supportL2:
    case UserRole.admin:
    case UserRole.unassigned:
      return location == Routes.blocked ? null : Routes.blocked;
  }
}

/// Allows only an in-app patient booking URL to survive the public sign-in
/// hand-off. Kept separate from [resolveRedirect] so the allow-list is tested
/// without constructing a router state.
@visibleForTesting
String? bookingReturnPath(String? returnTo) {
  final uri = returnTo == null ? null : Uri.tryParse(returnTo);
  if (uri != null &&
      !uri.hasScheme &&
      !uri.hasAuthority &&
      RegExp(r'^/patient/doctors/[^/]+/book$').hasMatch(uri.path)) {
    return uri.toString();
  }
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: ref.watch(_routerRefreshProvider),
    redirect: (context, state) {
      final sessionAsync = ref.read(sessionControllerProvider);
      // Route names only, never arguments: a breadcrumb carrying a record id
      // would put clinical context into a crash report.
      CrashReporting.breadcrumb(state.matchedLocation);
      final redirect = resolveRedirect(
        location: state.matchedLocation,
        sessionLoading: sessionAsync.isLoading,
        session: sessionAsync.value,
        onboardingComplete: ref.read(onboardingControllerProvider),
      );

      // A person can browse availability before authenticating. Once a patient
      // signs in, return them to the selected doctor's booking flow rather than
      // making them search for that doctor again. Only this exact internal
      // booking path is accepted; an arbitrary return URL must never be a
      // redirect target.
      if (redirect == Routes.patientHome && state.matchedLocation == Routes.login) {
        final returnTo = bookingReturnPath(
          state.uri.queryParameters['returnTo'],
        );
        if (returnTo != null) return returnTo;
      }
      return redirect;
    },
    routes: buildRoutes(),
  );
});
