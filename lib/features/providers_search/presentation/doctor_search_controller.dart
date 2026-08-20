import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../domain/doctor.dart';

/// Current search filters. Held separately from results so changing a filter
/// does not throw away the list already on screen.
class DoctorSearchFiltersNotifier extends Notifier<DoctorSearchFilters> {
  @override
  DoctorSearchFilters build() => const DoctorSearchFilters();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setSpecialty(String? code) =>
      state = state.copyWith(specialtyCode: code);

  void setCity(String? city) => state = state.copyWith(city: city);

  void setMaxFee(int? fee) => state = state.copyWith(maxFeeInr: fee);

  void setMinRating(double? rating) =>
      state = state.copyWith(minRating: rating);

  void setMode(ConsultationMode? mode) => state = state.copyWith(mode: mode);

  void setAvailableToday(bool value) =>
      state = state.copyWith(availableToday: value);

  void clearFilters() => state = DoctorSearchFilters(query: state.query);

  void clearAll() => state = const DoctorSearchFilters();
}

final doctorSearchFiltersProvider =
    NotifierProvider<DoctorSearchFiltersNotifier, DoctorSearchFilters>(
  DoctorSearchFiltersNotifier.new,
);

/// Search results for the current filters.
///
/// Re-runs whenever any filter changes. Debouncing lives in the search field so
/// that typing does not fire a request per keystroke.
final doctorSearchResultsProvider = FutureProvider<List<Doctor>>((ref) async {
  final filters = ref.watch(doctorSearchFiltersProvider);
  return ref.watch(doctorRepositoryProvider).search(filters);
});

final doctorByIdProvider =
    FutureProvider.family<Doctor, String>((ref, id) async {
  return ref.watch(doctorRepositoryProvider).byId(id);
});
