import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/prescription.dart';
import 'prescription_repository.dart';

/// Prescriptions against the MiDoctor API.
///
/// The client's drug-list checks are a courtesy — they let a doctor see why an
/// option is unavailable instead of composing something that will be refused.
/// The rule is enforced server-side, which re-resolves every item by id and
/// derives follow-up status from appointment history rather than believing the
/// request.
class ApiPrescriptionRepository implements PrescriptionRepository {
  ApiPrescriptionRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Prescription>> listForPatient() async {
    final json = await _api.get<List<dynamic>>('/v1/prescriptions');
    return json
        .map((e) => Prescription.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Prescription> byId(String id) async {
    final json = await _api.get<Map<String, dynamic>>('/v1/prescriptions/$id');
    return Prescription.fromJson(json);
  }

  @override
  Future<({String url, String? sha256})?> officialPdf(String id) async {
    try {
      final json =
          await _api.get<Map<String, dynamic>>('/v1/prescriptions/$id/pdf');
      final url = json['url'] as String?;
      if (url == null) return null;
      return (url: url, sha256: json['sha256'] as String?);
    } on Failure catch (f) {
      // PRESCRIPTION_PDF_PENDING is the documented "not yet" and must not
      // surface as an error — the caller renders locally instead. Anything
      // else is a real failure and is worth telling the user about.
      if (f.code == 'PRESCRIPTION_PDF_PENDING') return null;
      rethrow;
    }
  }

  @override
  Future<List<Drug>> searchDrugs(String query) async {
    if (query.trim().length < 2) return const [];
    final json = await _api.get<List<dynamic>>(
      '/v1/prescriptions/drugs',
      query: {'q': query.trim()},
    );
    return json
        .map((e) => Drug.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Prescription> issue({
    required String appointmentId,
    required String patientName,
    required String patientAge,
    required String patientGender,
    required List<PrescriptionItem> items,
    required bool isFollowUp,
    String? diagnosis,
    String? advice,
    DateTime? followUpDate,
  }) async {
    // Patient identity and follow-up status are part of the contract but are
    // deliberately not sent. Both decide what may legally be prescribed, so
    // both are derived server-side from the appointment and its history — a
    // client that could assert "this is a follow-up" could unlock List B.
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/prescriptions',
      body: {
        'appointmentId': appointmentId,
        'items': items
            .map((i) => {
                  'drugId': i.drugId,
                  'strength': i.strength,
                  'frequency': i.frequency,
                  'durationDays': i.durationDays,
                  if (i.instructions != null) 'instructions': i.instructions,
                })
            .toList(growable: false),
        if (diagnosis != null && diagnosis.isNotEmpty) 'diagnosis': diagnosis,
        if (advice != null && advice.isNotEmpty) 'advice': advice,
        if (followUpDate != null)
          'followUpDate': '${followUpDate.year.toString().padLeft(4, '0')}-'
              '${followUpDate.month.toString().padLeft(2, '0')}-'
              '${followUpDate.day.toString().padLeft(2, '0')}',
      },
    );
    return Prescription.fromJson(json);
  }
}
