import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_providers.dart';
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
