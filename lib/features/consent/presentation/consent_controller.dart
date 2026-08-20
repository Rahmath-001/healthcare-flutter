import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../domain/consent.dart';

final grantsProvider = FutureProvider<List<RecordAccessGrant>>((ref) async {
  return ref.watch(consentRepositoryProvider).grants();
});

final pendingRequestsProvider =
    FutureProvider<List<RecordAccessRequest>>((ref) async {
  return ref.watch(consentRepositoryProvider).pendingRequests();
});

final accessLogProvider = FutureProvider<List<RecordAccessEvent>>((ref) async {
  return ref.watch(consentRepositoryProvider).accessLog();
});

/// Number of pending access requests, for the badge on the Sharing entry point.
///
/// A request the patient never notices is functionally a denial, so this is
/// surfaced rather than left to be discovered.
final pendingRequestCountProvider = Provider<int>((ref) {
  return ref.watch(pendingRequestsProvider).value?.length ?? 0;
});

/// Revokes a grant and refreshes everything that displayed it.
Future<void> revokeGrant(WidgetRef ref, String grantId) async {
  await ref.read(consentRepositoryProvider).revoke(grantId);
  ref.invalidate(grantsProvider);
  ref.invalidate(accessLogProvider);
}
