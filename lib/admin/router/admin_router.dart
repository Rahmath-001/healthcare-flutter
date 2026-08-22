import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/session/session.dart';
import '../admin_app.dart';
import '../screens/admin_shell.dart';
import '../screens/audit_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/operator_sign_in_screen.dart';
import '../screens/provider_review_screen.dart';
import '../screens/rating_moderation_screen.dart';
import '../screens/review_queue_screen.dart';
import '../screens/support_queue_screen.dart';
import '../screens/support_ticket_screen.dart';
import '../screens/user_admin_screen.dart';

abstract final class AdminRoutes {
  static const signIn = '/sign-in';
  static const dashboard = '/';
  static const audit = '/audit';
  static const queue = '/queue';
  static const users = '/users';
  static const ratings = '/ratings';
  static const tickets = '/tickets';

  static String provider(String userId) => '/queue/$userId';
  static String ticket(String id) => '/tickets/$id';
}

/// Where an operator belongs.
///
/// Pure and separate from the mobile `resolveRedirect` even though both answer
/// the same shape of question, because they answer it about different people.
/// Sharing one function would mean one edit could let a patient into the review
/// queue, which is the single worst outcome this codebase can produce.
@visibleForTesting
String? resolveAdminRedirect({
  required String location,
  required bool sessionLoading,
  required Session? session,
}) {
  final isSignIn = location == AdminRoutes.signIn;

  if (sessionLoading) return null;

  if (session == null) return isSignIn ? null : AdminRoutes.signIn;

  // A suspended operator is an operator who has been stopped. The mobile app
  // shows a terminal explanation; here there is nothing to explain to — the
  // console is a tool, not a service they are a customer of.
  if (!session.isUsable) return isSignIn ? null : AdminRoutes.signIn;

  // A patient or a provider who reaches this URL is refused. They have their
  // own app, and their token carries none of the scopes anything here needs —
  // so this is a courtesy that keeps them from a broken-looking page, not the
  // control. The control is server-side.
  if (!isOperator(session)) return isSignIn ? null : AdminRoutes.signIn;

  if (isSignIn) return AdminRoutes.queue;
  return null;
}

class _AdminRefresh extends ChangeNotifier {
  _AdminRefresh(Ref ref) {
    ref.listen(sessionControllerProvider, (_, __) => notifyListeners());
  }
}

final _adminRefreshProvider = Provider<_AdminRefresh>((ref) {
  final refresh = _AdminRefresh(ref);
  ref.onDispose(refresh.dispose);
  return refresh;
});

final adminRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AdminRoutes.queue,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: ref.watch(_adminRefreshProvider),
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      return resolveAdminRedirect(
        location: state.matchedLocation,
        sessionLoading: session.isLoading,
        session: session.value,
      );
    },
    routes: [
      GoRoute(
        path: AdminRoutes.signIn,
        builder: (_, __) => const OperatorSignInScreen(),
      ),
      // A shell rather than separate scaffolds: an operator moves between the
      // queue and a ticket constantly, and losing the navigation on every push
      // is what makes an internal tool feel like a form.
      ShellRoute(
        builder: (_, state, child) =>
            AdminShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: AdminRoutes.dashboard,
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: AdminRoutes.audit,
            builder: (_, __) => const AuditScreen(),
          ),
          GoRoute(
            path: AdminRoutes.queue,
            builder: (_, __) => const ReviewQueueScreen(),
            routes: [
              GoRoute(
                path: ':userId',
                builder: (_, state) => ProviderReviewScreen(
                  userId: state.pathParameters['userId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: AdminRoutes.users,
            builder: (_, __) => const UserAdminScreen(),
          ),
          GoRoute(
            path: AdminRoutes.ratings,
            builder: (_, __) => const RatingModerationScreen(),
          ),
          GoRoute(
            path: AdminRoutes.tickets,
            builder: (_, __) => const SupportQueueScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    SupportTicketScreen(ticketId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
