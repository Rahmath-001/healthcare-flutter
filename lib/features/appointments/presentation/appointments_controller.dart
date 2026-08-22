import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
import '../../booking/presentation/booking_controller.dart';
import '../domain/appointment.dart';

final patientAppointmentsProvider =
    FutureProvider<List<Appointment>>((ref) async {
  return ref.watch(appointmentRepositoryProvider).listForPatient();
});

final providerAppointmentsProvider =
    FutureProvider<List<Appointment>>((ref) async {
  return ref.watch(appointmentRepositoryProvider).listForProvider();
});

final appointmentByIdProvider =
    FutureProvider.family<Appointment, String>((ref, id) async {
  return ref.watch(appointmentRepositoryProvider).byId(id);
});

/// Appointments the provider is seeing today, in start order.
final providerTodayProvider = FutureProvider<List<Appointment>>((ref) async {
  final all = await ref.watch(providerAppointmentsProvider.future);
  final now = DateTime.now();
  return all
      .where((a) =>
          a.start.year == now.year &&
          a.start.month == now.month &&
          a.start.day == now.day &&
          !a.status.isCancelled)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
});

/// Cancels an appointment and refreshes every list that showed it.
/// Moves an appointment and refreshes everything that showed it at the old time.
///
/// The slot providers are invalidated too, and that is not housekeeping: the
/// day the appointment left now has a slot free and the day it moved to has one
/// fewer. A patient who reschedules and then immediately reopens the picker
/// would otherwise be looking at a cached grid that still shows their old time
/// as taken and their new time as available.
Future<Appointment> rescheduleAppointment(
  WidgetRef ref,
  String id, {
  required DateTime start,
  required DateTime end,
}) async {
  final result = await ref
      .read(appointmentRepositoryProvider)
      .reschedule(id, start: start, end: end);
  ref.invalidate(patientAppointmentsProvider);
  ref.invalidate(providerAppointmentsProvider);
  ref.invalidate(providerTodayProvider);
  ref.invalidate(appointmentByIdProvider(id));
  ref.invalidate(slotsProvider);
  return result;
}

Future<Appointment> cancelAppointment(
  WidgetRef ref,
  String id, {
  required String reason,
}) async {
  final result =
      await ref.read(appointmentRepositoryProvider).cancel(id, reason: reason);
  ref.invalidate(patientAppointmentsProvider);
  ref.invalidate(providerAppointmentsProvider);
  ref.invalidate(appointmentByIdProvider(id));
  return result;
}
