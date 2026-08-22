import '../../../core/network/api_client.dart';
import '../domain/appointment.dart';
import 'appointment_repository.dart';

/// API-backed [AppointmentRepository].
///
/// Patient and provider hit the same endpoint. Which list comes back is decided
/// from the access token, never from a parameter — a patient cannot ask for a
/// provider's schedule by changing a query string.
class ApiAppointmentRepository implements AppointmentRepository {
  ApiAppointmentRepository(this._api);

  final ApiClient _api;

  Future<List<Appointment>> _list() async {
    final json = await _api.get<Map<String, dynamic>>('/v1/appointments');
    return (json['items'] as List<dynamic>)
        .map((a) => Appointment.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Appointment>> listForPatient() => _list();

  @override
  Future<List<Appointment>> listForProvider() => _list();

  @override
  Future<Appointment> byId(String id) async {
    final json = await _api.get<Map<String, dynamic>>('/v1/appointments/$id');
    return Appointment.fromJson(json);
  }

  @override
  Future<Appointment> cancel(String id, {required String reason}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/appointments/$id/cancel',
      body: {'reason': reason},
    );
    return Appointment.fromJson(json);
  }

  @override
  Future<Appointment> reschedule(
    String id, {
    required DateTime start,
    required DateTime end,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/appointments/$id/reschedule',
      // The instant, in UTC. The server derives the slot id and the IST
      // calendar day from it — the client never composes a slot id, because
      // that id is the entire no-double-booking guarantee and a client that
      // builds it can build a wrong one.
      body: {'start': start.toUtc().toIso8601String()},
    );
    return Appointment.fromJson(json);
  }

  @override
  Future<Appointment> checkIn(String id) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/appointments/$id/check-in',
    );
    return Appointment.fromJson(json);
  }
}
