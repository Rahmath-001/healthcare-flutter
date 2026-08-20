import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../features/support/domain/support_ticket.dart';
import '../data/fixture_operations_repository.dart';
import '../data/operations_repository.dart';

/// Composition root for the operator console.
///
/// Deliberately thin: it reuses `apiClientProvider` from `lib/core`, so the
/// console gets the same `AuthInterceptor`, the same single-flight refresh and
/// the same `Failure` mapping as the app. A second HTTP stack for staff would
/// be a second place for token handling to be wrong.
final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureOperationsRepository();
  return ApiOperationsRepository(ref.watch(apiClientProvider));
});

final reviewQueueProvider =
    FutureProvider<List<ProviderApplication>>((ref) async {
  return ref.watch(operationsRepositoryProvider).reviewQueue();
});

final providerDossierProvider =
    FutureProvider.family<ProviderDossier, String>((ref, userId) async {
  return ref.watch(operationsRepositoryProvider).dossier(userId);
});

final pendingRatingsProvider = FutureProvider<List<PendingRating>>((ref) async {
  return ref.watch(operationsRepositoryProvider).pendingRatings();
});

/// Which slice of the support queue is on screen.
class TicketFilterNotifier extends Notifier<TicketStatus?> {
  @override
  TicketStatus? build() => TicketStatus.open;

  void set(TicketStatus? status) => state = status;
}

final ticketFilterProvider =
    NotifierProvider<TicketFilterNotifier, TicketStatus?>(
  TicketFilterNotifier.new,
);

final ticketQueueProvider = FutureProvider<List<QueuedTicket>>((ref) async {
  final status = ref.watch(ticketFilterProvider);
  return ref.watch(operationsRepositoryProvider).ticketQueue(status: status);
});

final ticketProvider =
    FutureProvider.family<SupportTicket, String>((ref, id) async {
  return ref.watch(operationsRepositoryProvider).ticket(id);
});

/// One user looked up by id, for the accounts screen.
///
/// A family rather than a search endpoint because there is no user-search API,
/// and inventing one would mean an endpoint that returns people matching a
/// substring — which is a very different thing to hand a helpdesk than "show me
/// this specific account".
final userLookupProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  return ref.watch(operationsRepositoryProvider).lookupUser(userId);
});
