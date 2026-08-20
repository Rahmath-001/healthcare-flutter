import '../../../core/fixtures/fixture_backend.dart';
import '../domain/appointment.dart';

abstract class AppointmentRepository {
  /// Patient's own appointments.
  Future<List<Appointment>> listForPatient();

  /// Appointments for the signed-in provider. The `appointments:read_own` scope
  /// limits this to that provider's own patients.
  Future<List<Appointment>> listForProvider();

  Future<Appointment> byId(String id);

  Future<Appointment> cancel(String id, {required String reason});

  /// Provider-side check-in, moving CONFIRMED to CHECKED_IN.
  Future<Appointment> checkIn(String id);
}

class FixtureAppointmentRepository implements AppointmentRepository {
  FixtureAppointmentRepository({
    this.latency = const Duration(milliseconds: 350),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<List<Appointment>> listForPatient() async {
    await Future<void>.delayed(latency);
    return _backend.appointments();
  }

  /// The provider's own list.
  ///
  /// The fixture has one patient, so this is the same set seen from the other
  /// side — which is the useful shape for exercising the provider shell without
  /// inventing a second person's clinical history.
  @override
  Future<List<Appointment>> listForProvider() async {
    await Future<void>.delayed(latency);
    return _backend.appointments();
  }

  @override
  Future<Appointment> byId(String id) async {
    await Future<void>.delayed(latency);
    return _backend.appointmentById(id);
  }

  @override
  Future<Appointment> cancel(String id, {required String reason}) async {
    await Future<void>.delayed(latency);
    return _backend.cancelAppointment(id, reason: reason);
  }

  @override
  Future<Appointment> checkIn(String id) async {
    await Future<void>.delayed(latency);
    return _backend.checkIn(id);
  }
}
