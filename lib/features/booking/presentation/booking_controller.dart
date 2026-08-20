import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../../appointments/domain/appointment.dart';
import '../../providers_search/domain/doctor.dart';

/// Identifies one day of slots for one doctor in one mode.
class SlotQuery {
  const SlotQuery({
    required this.doctorId,
    required this.date,
    required this.mode,
  });

  final String doctorId;
  final DateTime date;
  final ConsultationMode mode;

  @override
  bool operator ==(Object other) =>
      other is SlotQuery &&
      other.doctorId == doctorId &&
      other.mode == mode &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode =>
      Object.hash(doctorId, mode, date.year, date.month, date.day);
}

/// Slots for a given doctor, day and mode.
///
/// `autoDispose` matters here: a patient browsing a week of dates would
/// otherwise accumulate a cached list per day for the life of the screen.
final slotsProvider =
    FutureProvider.autoDispose.family<List<AppointmentSlot>, SlotQuery>(
  (ref, query) async {
    return ref.watch(bookingRepositoryProvider).slotsFor(
          doctorId: query.doctorId,
          date: query.date,
          mode: query.mode,
        );
  },
);

/// State of an in-progress booking.
class BookingState {
  const BookingState({
    this.selectedDate,
    this.mode = ConsultationMode.video,
    this.selectedSlot,
    this.hold,
    this.isBooking = false,
  });

  final DateTime? selectedDate;
  final ConsultationMode mode;
  final AppointmentSlot? selectedSlot;
  final SlotHold? hold;
  final bool isBooking;

  BookingState copyWith({
    DateTime? selectedDate,
    ConsultationMode? mode,
    Object? selectedSlot = _unset,
    Object? hold = _unset,
    bool? isBooking,
  }) =>
      BookingState(
        selectedDate: selectedDate ?? this.selectedDate,
        mode: mode ?? this.mode,
        selectedSlot: selectedSlot == _unset
            ? this.selectedSlot
            : selectedSlot as AppointmentSlot?,
        hold: hold == _unset ? this.hold : hold as SlotHold?,
        isBooking: isBooking ?? this.isBooking,
      );

  static const _unset = Object();
}

class BookingController extends Notifier<BookingState> {
  @override
  BookingState build() {
    final now = DateTime.now();
    return BookingState(selectedDate: DateTime(now.year, now.month, now.day));
  }

  void selectDate(DateTime date) => state = state.copyWith(
        selectedDate: DateTime(date.year, date.month, date.day),
        selectedSlot: null,
      );

  void selectMode(ConsultationMode mode) =>
      state = state.copyWith(mode: mode, selectedSlot: null);

  /// Reserves the slot for ten minutes so the patient can confirm without
  /// racing another booking, and without holding it indefinitely.
  Future<void> selectSlot(AppointmentSlot slot) async {
    state = state.copyWith(selectedSlot: slot);
    final hold = await ref.read(bookingRepositoryProvider).hold(slot.id);
    state = state.copyWith(hold: hold);
  }

  Future<void> releaseHold() async {
    final slot = state.selectedSlot;
    if (slot == null) return;
    await ref.read(bookingRepositoryProvider).releaseHold(slot.id);
    state = state.copyWith(selectedSlot: null, hold: null);
  }

  Future<Appointment> confirm({
    required Doctor doctor,
    required String patientName,
    String? reasonForVisit,
  }) async {
    final slot = state.selectedSlot;
    if (slot == null) {
      throw StateError('No slot selected');
    }

    state = state.copyWith(isBooking: true);
    try {
      final appointment = await ref.read(bookingRepositoryProvider).book(
            doctor: doctor,
            slot: slot,
            mode: state.mode,
            patientName: patientName,
            reasonForVisit: reasonForVisit,
          );
      return appointment;
    } finally {
      state = state.copyWith(isBooking: false);
    }
  }
}

final bookingControllerProvider =
    NotifierProvider.autoDispose<BookingController, BookingState>(
  BookingController.new,
);
