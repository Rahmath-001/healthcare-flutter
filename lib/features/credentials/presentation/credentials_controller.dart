import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../domain/credential.dart';

final verificationChecklistProvider =
    FutureProvider<VerificationChecklist>((ref) async {
  return ref.watch(credentialsRepositoryProvider).checklist();
});

/// Invalidates the checklist after any mutation, so the progress indicator and
/// the submit gate always agree with the server.
void refreshChecklist(WidgetRef ref) =>
    ref.invalidate(verificationChecklistProvider);
