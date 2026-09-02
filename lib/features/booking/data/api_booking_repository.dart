import '../../appointments/domain/appointment.dart';
import '../domain/waitlist.dart';
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
        'date': _dateOnly(date),
        'mode': mode.wire,
      },
    );

    return (json['items'] as List<dynamic>)
        .map((s) => AppointmentSlot.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// The API treats the requested day as an IST calendar date, never as an
  /// instant. Sending `toIso8601String()` here would include a time component
  /// and is correctly rejected by the server's strict `YYYY-MM-DD` contract.
  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  Future<List<WaitlistEntry>> waitlist() async {
    final json = await _api.get<List<dynamic>>('/v1/waitlist');
    return json
        .map((e) => WaitlistEntry.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<WaitlistEntry> joinWaitlist({
    required Doctor doctor,
    required ConsultationMode mode,
    DateTime? preferredDate,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/waitlist',
      // The doctor's name is snapshotted server-side from the directory, so
      // only the id is sent — a client cannot enter itself on a list under a
      // name of its choosing.
      body: {
        'doctorId': doctor.id,
        'mode': mode.wire,
        if (preferredDate != null)
          'preferredDate': '${preferredDate.year.toString().padLeft(4, '0')}-'
              '${preferredDate.month.toString().padLeft(2, '0')}-'
              '${preferredDate.day.toString().padLeft(2, '0')}',
      },
    );
    return WaitlistEntry.fromJson(json);
  }

  @override
  Future<WaitlistEntry> leaveWaitlist(String id) async {
    final json = await _api.delete<Map<String, dynamic>>('/v1/waitlist/$id');
    return WaitlistEntry.fromJson(json);
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
