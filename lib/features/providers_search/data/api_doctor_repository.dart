import '../../../core/network/api_client.dart';
import '../domain/doctor.dart';
import 'doctor_repository.dart';

/// API-backed [DoctorRepository].
///
/// Free text, fee ceiling and minimum rating are sent to the server rather than
/// applied here: filtering client-side would mean downloading the directory,
/// and "show me doctors under ₹500" would leak the ones over it.
class ApiDoctorRepository implements DoctorRepository {
  ApiDoctorRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Doctor>> search(DoctorSearchFilters filters) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/doctors',
      query: {
        if (filters.query.trim().isNotEmpty) 'query': filters.query.trim(),
        if (filters.specialtyCode != null)
          'specialtyCode': filters.specialtyCode,
        if (filters.city != null) 'city': filters.city,
        if (filters.maxFeeInr != null) 'maxFeeInr': filters.maxFeeInr,
        if (filters.minRating != null) 'minRating': filters.minRating,
        if (filters.mode != null) 'mode': filters.mode!.wire,
      },
    );

    return (json['items'] as List<dynamic>)
        .map((d) => Doctor.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Doctor> byId(String id) async {
    final json = await _api.get<Map<String, dynamic>>('/v1/doctors/$id');
    return Doctor.fromJson(json);
  }

  @override
  Future<List<Specialty>> specialties() async {
    final json =
        await _api.get<Map<String, dynamic>>('/v1/doctors/specialties');
    return (json['items'] as List<dynamic>)
        .map((s) => Specialty.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<String>> cities() async {
    final json = await _api.get<Map<String, dynamic>>('/v1/doctors/cities');
    return (json['items'] as List<dynamic>).map((c) => c.toString()).toList();
  }
}
