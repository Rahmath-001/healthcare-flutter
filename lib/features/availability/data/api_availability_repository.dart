import '../../../core/network/api_client.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/availability.dart';
import 'availability_repository.dart';

/// A provider's working hours, against the MiDoctor API.
///
/// Slots are never stored — the server materialises them from these rules on
/// demand — so an edit here takes effect on the next search rather than waiting
/// for a generation job.
class ApiAvailabilityRepository implements AvailabilityRepository {
  ApiAvailabilityRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AvailabilityRule>> rules() async {
    final json = await _api.get<List<dynamic>>('/v1/availability/rules');
    return json
        .map((e) => AvailabilityRule.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<AvailabilityException>> exceptions() async {
    final json = await _api.get<List<dynamic>>('/v1/availability/exceptions');
    return json
        .map((e) => AvailabilityException.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<AvailabilityRule> addRule({
    required int weekday,
    required TimeOfDayValue start,
    required TimeOfDayValue end,
    required ConsultationMode mode,
    required int slotMinutes,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/availability/rules',
      body: {
        'weekday': weekday,
        'startMinutes': start.totalMinutes,
        'endMinutes': end.totalMinutes,
        'mode': mode.wire,
        'slotMinutes': slotMinutes,
      },
    );
    return AvailabilityRule.fromJson(json);
  }

  @override
  Future<void> deleteRule(String id) =>
      _api.delete<Map<String, dynamic>>('/v1/availability/rules/$id');

  @override
  Future<AvailabilityRule> toggleRule(String id, {required bool active}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/availability/rules/$id/toggle',
      body: {'active': active},
    );
    return AvailabilityRule.fromJson(json);
  }

  @override
  Future<AvailabilityException> blockDay(DateTime date,
      {String? reason}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/availability/exceptions',
      body: {
        // A blocked day is a calendar day. Sending an instant would shift it.
        'date': '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return AvailabilityException.fromJson(json);
  }

  @override
  Future<void> deleteException(String id) =>
      _api.delete<Map<String, dynamic>>('/v1/availability/exceptions/$id');
}
