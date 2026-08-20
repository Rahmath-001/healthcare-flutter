import '../../../core/error/failure.dart';
import '../domain/doctor.dart';
import 'doctor_fixtures.dart';

/// Provider search and profile lookup.
///
/// Only APPROVED providers are ever returned: an unverified provider holds no
/// search visibility at all, which is why there is no status filter here.
abstract class DoctorRepository {
  Future<List<Doctor>> search(DoctorSearchFilters filters);
  Future<Doctor> byId(String id);
  Future<List<Specialty>> specialties();
  Future<List<String>> cities();
}

class FixtureDoctorRepository implements DoctorRepository {
  FixtureDoctorRepository({this.latency = const Duration(milliseconds: 400)});

  final Duration latency;

  @override
  Future<List<Doctor>> search(DoctorSearchFilters filters) async {
    await Future<void>.delayed(latency);

    final q = filters.query.trim().toLowerCase();
    final results = DoctorFixtures.all.where((d) {
      if (q.isNotEmpty) {
        // Matches the server's pg_trgm search surface: name, specialty,
        // hospital and city are all searchable (FR-SRCH-001).
        final haystack = [
          d.name,
          d.specialtyLabel,
          d.hospital.name,
          d.hospital.city,
        ].join(' ').toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      if (filters.specialtyCode != null &&
          !d.specialties.any((s) => s.code == filters.specialtyCode)) {
        return false;
      }
      if (filters.city != null && d.hospital.city != filters.city) return false;
      if (filters.maxFeeInr != null &&
          d.consultationFeeInr > filters.maxFeeInr!) {
        return false;
      }
      if (filters.minRating != null && d.rating < filters.minRating!) {
        return false;
      }
      if (filters.mode != null && !d.modes.contains(filters.mode)) return false;
      if (filters.availableToday && !_hasSlotToday()) return false;
      return true;
    }).toList()
      // Highest rated first; the API will paginate with a cursor.
      ..sort((a, b) => b.rating.compareTo(a.rating));

    return results;
  }

  /// Whether any slot remains today.
  ///
  /// The API answers this from the materialised slot table. Here it mirrors the
  /// booking fixture's own rules — closed Sundays, clinic hours ending at
  /// 18:00 — so this filter and the slot grid never disagree.
  static bool _hasSlotToday() {
    final now = DateTime.now();
    if (now.weekday == DateTime.sunday) return false;
    return now.hour < 18;
  }

  @override
  Future<Doctor> byId(String id) async {
    await Future<void>.delayed(latency);
    try {
      return DoctorFixtures.byId(id);
    } on StateError {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'This doctor is no longer available.',
        code: 'DOCTOR_NOT_FOUND',
      );
    }
  }

  @override
  Future<List<Specialty>> specialties() async => DoctorFixtures.specialties;

  @override
  Future<List<String>> cities() async => DoctorFixtures.cities;
}
