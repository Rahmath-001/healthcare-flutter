import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../domain/patient_profile.dart';

/// The signed-in patient's own profile.
///
/// Read on demand rather than held in the session: the session exists to answer
/// "what may this caller do", and blood group is not part of that answer.
final patientProfileProvider = FutureProvider<PatientProfile>((ref) async {
  return ref.watch(accountRepositoryProvider).profile();
});
