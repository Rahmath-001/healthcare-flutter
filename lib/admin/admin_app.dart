import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/session/session.dart';
import '../core/session/user_role.dart';
import 'router/admin_router.dart';
import 'theme/admin_theme.dart';

/// The MiDoctor operator console.
///
/// A **separate entry point**, not a third shell inside the patient app, and
/// the distinction matters for more than tidiness:
///
///  - Supervisor and admin roles are deliberately routed to `/blocked` on
///    mobile. Reviewing a doctor's degree certificate on a phone is not a thing
///    anyone should do, and modelling it as "another tab" would invite it.
///  - Nothing under `lib/admin/` is reachable from `lib/main.dart`, so none of
///    it is compiled into the APK a patient installs. Approval logic and
///    reviewer copy stay out of a binary that ships to the people being
///    reviewed.
///  - It can be deployed behind whatever an operations team already uses —
///    a VPN, an IdP, an allow-list — without any of that touching the app.
///
/// Everything below `lib/admin/` reuses `lib/core`: the same `ApiClient`, the
/// same `Failure`, the same session and refresh machinery. Only the shell,
/// routing and screens differ, because the *authorization* story is identical
/// and having two of those is how they drift.
class MiDoctorAdminApp extends ConsumerWidget {
  const MiDoctorAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MiDoctor Operations',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light,
      darkTheme: AdminTheme.dark,
      routerConfig: ref.watch(adminRouterProvider),
    );
  }
}

/// Roles this console is for.
///
/// The exact complement of the mobile app's supported roles: a patient or a
/// provider signing in here is refused, just as a supervisor is refused there.
/// One place decides, and it decides from the server-issued session rather than
/// from anything the browser could assert.
bool isOperator(Session? session) {
  if (session == null) return false;
  return switch (session.role) {
    UserRole.supervisor || UserRole.admin => true,
    UserRole.supportL1 || UserRole.supportL2 => true,
    UserRole.patient || UserRole.provider || UserRole.unassigned => false,
  };
}

/// Convenience for screens that need to know what the operator may do.
///
/// Reads the same `scopes` claim the API enforces against, so a button is
/// hidden for exactly the reason the endpoint behind it would refuse — rather
/// than for a second, hand-maintained reason that can drift from it.
final operatorScopesProvider = Provider<Set<String>>((ref) {
  final session = ref.watch(currentSessionProvider);
  return session?.scopes.toSet() ?? const <String>{};
});

extension OperatorAccess on Set<String> {
  bool get canReviewProviders => _has('provider:review');
  bool get canDecideProviders => _has('provider:approve');
  bool get canSuspendAccounts => _has('user:suspend');
  bool get canAssignRoles => _has('user:set_role');
  bool get canReadTickets => _has('support:ticket_read');
  bool get canEscalateTickets => _has('support:ticket_escalate');

  bool _has(String scope) => contains('*:*') || contains(scope);
}
