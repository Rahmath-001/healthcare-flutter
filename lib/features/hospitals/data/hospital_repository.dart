import '../../../core/network/api_client.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/hospital.dart';

/// Public directory of operator-approved hospitals and their approved doctors.
abstract class HospitalRepository {
  Future<List<HospitalDirectoryEntry>> list({String query, String? city});
  Future<HospitalDirectoryEntry> byId(String id);
  Future<List<Doctor>> doctors(String hospitalId);
  Future<HospitalDirectoryEntry> mine();
  Future<List<HospitalManagementRequest>> managementRequests();
  Future<HospitalManagementRequest> submitProfileChange({
    required String name,
    required String address,
    required String city,
    required String state,
    required String postalCode,
  });
  Future<HospitalManagementRequest> requestAffiliation(String doctorId);
}

class ApiHospitalRepository implements HospitalRepository {
  ApiHospitalRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<HospitalDirectoryEntry>> list({
    String query = '',
    String? city,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/hospitals',
      query: {
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      },
    );
    return (json['items'] as List<dynamic>)
        .map((entry) =>
            HospitalDirectoryEntry.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<HospitalDirectoryEntry> byId(String id) async {
    final json = await _api.get<Map<String, dynamic>>('/v1/hospitals/$id');
    return HospitalDirectoryEntry.fromJson(json);
  }

  @override
  Future<List<Doctor>> doctors(String hospitalId) async {
    final json = await _api
        .get<Map<String, dynamic>>('/v1/hospitals/$hospitalId/doctors');
    return (json['items'] as List<dynamic>)
        .map((entry) => Doctor.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<HospitalDirectoryEntry> mine() async {
    final json = await _api.get<Map<String, dynamic>>('/v1/hospitals/mine');
    return HospitalDirectoryEntry.fromJson(json);
  }

  @override
  Future<List<HospitalManagementRequest>> managementRequests() async {
    final json =
        await _api.get<Map<String, dynamic>>('/v1/hospitals/mine/requests');
    return (json['items'] as List<dynamic>)
        .map((entry) => HospitalManagementRequest.fromJson(
            entry as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<HospitalManagementRequest> submitProfileChange({
    required String name,
    required String address,
    required String city,
    required String state,
    required String postalCode,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/hospitals/mine/change-requests',
      body: {
        'name': name,
        'address': address,
        'city': city,
        'state': state,
        'postalCode': postalCode,
      },
    );
    return HospitalManagementRequest.fromJson(json);
  }

  @override
  Future<HospitalManagementRequest> requestAffiliation(String doctorId) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/hospitals/mine/affiliation-requests',
      body: {'doctorId': doctorId},
    );
    return HospitalManagementRequest.fromJson(json);
  }
}
