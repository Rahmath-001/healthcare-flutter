import '../../appointments/domain/appointment.dart';
import '../../../core/network/api_client.dart';
import '../../providers_search/domain/doctor.dart';
import 'booking_repository.dart';

/// API-backed [BookingRepository].
///
/// The slot id is opaque here on purpose: the server derives it from the doctor
/// and the exact start instant so that two phones booking the same slot address
/// the same row. Nothing on the client should parse or construct one.
class ApiBookingRepository implements BookingRepository {
  ApiBookingRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AppointmentSlot>> slotsFor({
    required String doctorId,
    required DateTime date,
    required ConsultationMode mode,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/doctors/$doctorId/slots',
      query: {
        // Date only: the server materialises a whole day from the doctor's
        // availability rules, so sending a time would imply a precision the
        // query does not have.
        'date': DateTime(date.year, date.month, date.day).toIso8601String(),
        'mode': mode.wire,
      },
    );

    return (json['items'] as List<dynamic>)
        .map((s) => AppointmentSlot.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SlotHold> hold(String slotId) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/slots/${Uri.encodeComponent(slotId)}/hold',
    );
    return SlotHold.fromJson(json);
  }

  @override
  Future<void> releaseHold(String slotId) async {
    await _api.delete<Map<String, dynamic>>(
      '/v1/slots/${Uri.encodeComponent(slotId)}/hold',
    );
  }

  @override
  Future<Appointment> book({
    required Doctor doctor,
    required AppointmentSlot slot,
    required ConsultationMode mode,
    required String patientName,
    String? reasonForVisit,
  }) async {
    // The doctor and fee are not sent: the server reads them from its own
    // records. A client that could name the fee could name a lower one.
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/appointments',
      body: {
        'slotId': slot.id,
        'mode': mode.wire,
        'patientName': patientName,
        if (reasonForVisit != null && reasonForVisit.trim().isNotEmpty)
          'reasonForVisit': reasonForVisit.trim(),
      },
    );
    return Appointment.fromJson(json);
  }
}
