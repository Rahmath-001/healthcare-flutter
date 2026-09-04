import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/hospital.dart';

final hospitalDirectoryProvider =
    FutureProvider<List<HospitalDirectoryEntry>>((ref) async {
  return ref.watch(hospitalRepositoryProvider).list();
});

final hospitalByIdProvider =
    FutureProvider.family<HospitalDirectoryEntry, String>((ref, id) async {
  return ref.watch(hospitalRepositoryProvider).byId(id);
});

final hospitalDoctorsProvider =
    FutureProvider.family<List<Doctor>, String>((ref, id) async {
  return ref.watch(hospitalRepositoryProvider).doctors(id);
});

/// The signed-in organisation's record. The API derives the id from the
/// access token; a hospital cannot substitute another hospital's id.
final myHospitalProvider = FutureProvider<HospitalDirectoryEntry>((ref) async {
  return ref.watch(hospitalRepositoryProvider).mine();
});

final hospitalManagementRequestsProvider =
    FutureProvider<List<HospitalManagementRequest>>((ref) async {
  return ref.watch(hospitalRepositoryProvider).managementRequests();
});
