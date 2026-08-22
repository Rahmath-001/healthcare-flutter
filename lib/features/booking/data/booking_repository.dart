import 'dart:math';

import '../../../core/fixtures/fixture_backend.dart';
import '../../appointments/domain/appointment.dart';
import '../domain/waitlist.dart';
import '../../providers_search/domain/doctor.dart';

/// Whether a booking must be paid for before it is confirmed.
///
/// FR-BOOK-003 requires payment, but payments are deferred, so this returns
/// false and a held slot goes straight to CONFIRMED with
/// `PaymentStatus.notRequired`. Flipping this to true is the entire change
/// needed to switch payments on: the extra PENDING_PAYMENT state and its
/// webhook transition already exist in the model.
abstract final class BookingPolicy {
  static bool requiresPayment() => false;
}

/// Slot discovery, holds, and booking.
abstract class BookingRepository {
  /// Slots for one doctor on one day. Materialised server-side, which is what
  /// makes double-booking a row-lock problem rather than an application race.
  Future<List<AppointmentSlot>> slotsFor({
    required String doctorId,
    required DateTime date,
    required ConsultationMode mode,
  });

  /// The caller's waitlist entries.
  Future<List<WaitlistEntry>> waitlist();

  /// Asks to be told when this doctor frees up.
  ///
  /// Being told is **not** a reservation. Holding a freed slot for whoever is
  /// first on a list means it sits empty while they are asleep or no longer
  /// interested — exactly the waste the cancellation was meant to recover.
  Future<WaitlistEntry> joinWaitlist({
    required Doctor doctor,
    required ConsultationMode mode,
    DateTime? preferredDate,
  });

  Future<WaitlistEntry> leaveWaitlist(String id);

  /// Reserves a slot for ten minutes while the patient confirms.
  Future<SlotHold> hold(String slotId);

  Future<void> releaseHold(String slotId);

  /// Confirms the booking. The server enforces uniqueness with an exclusion
  /// constraint, so a lost race surfaces here as a [FailureKind.conflict].
  Future<Appointment> book({
    required Doctor doctor,
    required AppointmentSlot slot,
    required ConsultationMode mode,
    required String patientName,
    String? reasonForVisit,
  });
}

class FixtureBookingRepository implements BookingRepository {
  FixtureBookingRepository({
    this.latency = const Duration(milliseconds: 350),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  /// Slots are materialised on demand from the doctor's working pattern, the
  /// way the server derives them from availability rules — so a slot that was
  /// booked, held or blocked disappears from the grid without anything having
  /// to remember to remove it.
  @override
  @override
  Future<List<WaitlistEntry>> waitlist() async {
    await Future<void>.delayed(latency);
    return _backend.waitlist();
  }

  @override
  Future<WaitlistEntry> joinWaitlist({
    required Doctor doctor,
    required ConsultationMode mode,
    DateTime? preferredDate,
  }) async {
    await Future<void>.delayed(latency);
    return _backend.joinWaitlist(
      doctor: doctor,
      mode: mode,
      preferredDate: preferredDate,
    );
  }

  @override
  Future<WaitlistEntry> leaveWaitlist(String id) async {
    await Future<void>.delayed(latency);
    return _backend.leaveWaitlist(id);
  }

  @override
  Future<List<AppointmentSlot>> slotsFor({
    required String doctorId,
    required DateTime date,
    required ConsultationMode mode,
  }) async {
    await Future<void>.delayed(latency);

    final day = DateTime(date.year, date.month, date.day);
    // Sundays are closed, which gives the UI a real empty state to render
    // rather than one that only appears in theory.
    if (day.weekday == DateTime.sunday) return const [];
    // A day the provider blocked in the availability editor produces nothing,
    // which is the behaviour the real backend had to be taught.
    if (_backend.isDayBlocked(day)) return const [];

    final slots = <AppointmentSlot>[];
    // Deterministic per doctor+day, so the pattern of already-busy slots does
    // not reshuffle on every rebuild.
    final random = Random(doctorId.hashCode ^ day.millisecondsSinceEpoch);

    for (var hour = 9; hour < 18; hour++) {
      if (hour == 13) continue; // lunch
      for (final minute in const [0, 30]) {
        final start = DateTime(day.year, day.month, day.day, hour, minute);
        if (start.isBefore(DateTime.now())) continue;

        final id = FixtureBackend.slotId(doctorId, start);
        // Someone else's booking, or ours: both make the slot unavailable, and
        // the second kind is what makes the flow feel real.
        final busy = _backend.isSlotTaken(id) || random.nextDouble() < 0.3;

        slots.add(AppointmentSlot(
          id: id,
          start: start,
          end: start.add(const Duration(minutes: 30)),
          mode: mode,
          isAvailable: !busy,
        ));
      }
    }
    return slots;
  }

  @override
  Future<SlotHold> hold(String slotId) async {
    await Future<void>.delayed(latency);
    _backend.holdSlot(slotId, SlotHold.duration);
    return SlotHold(
      slotId: slotId,
      expiresAt: DateTime.now().add(SlotHold.duration),
    );
  }

  @override
  Future<void> releaseHold(String slotId) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _backend.releaseSlot(slotId);
  }

  @override
  Future<Appointment> book({
    required Doctor doctor,
    required AppointmentSlot slot,
    required ConsultationMode mode,
    required String patientName,
    String? reasonForVisit,
  }) async {
    await Future<void>.delayed(latency);
    // Files it in the shared store, so it appears in the patient's own
    // appointments list rather than existing only as this call's return value.
    return _backend.book(
      doctor: doctor,
      start: slot.start,
      end: slot.end,
      mode: mode,
      patientName: patientName,
      reasonForVisit: reasonForVisit,
    );
  }
}
