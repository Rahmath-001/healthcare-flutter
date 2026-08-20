import '../../../core/fixtures/fixture_backend.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/availability.dart';

abstract class AvailabilityRepository {
  Future<List<AvailabilityRule>> rules();
  Future<List<AvailabilityException>> exceptions();

  Future<AvailabilityRule> addRule({
    required int weekday,
    required TimeOfDayValue start,
    required TimeOfDayValue end,
    required ConsultationMode mode,
    required int slotMinutes,
  });

  Future<void> deleteRule(String id);
  Future<AvailabilityRule> toggleRule(String id, {required bool active});

  Future<AvailabilityException> blockDay(DateTime date, {String? reason});
  Future<void> deleteException(String id);
}

class FixtureAvailabilityRepository implements AvailabilityRepository {
  FixtureAvailabilityRepository({
    this.latency = const Duration(milliseconds: 300),
    FixtureBackend? backend,
  }) : _backend = backend ?? FixtureBackend.shared;

  final Duration latency;
  final FixtureBackend _backend;

  @override
  Future<List<AvailabilityRule>> rules() async {
    await Future<void>.delayed(latency);
    return _backend.rules();
  }

  @override
  Future<List<AvailabilityException>> exceptions() async {
    await Future<void>.delayed(latency);
    return _backend.exceptions();
  }

  @override
  Future<AvailabilityRule> addRule({
    required int weekday,
    required TimeOfDayValue start,
    required TimeOfDayValue end,
    required ConsultationMode mode,
    required int slotMinutes,
  }) async {
    await Future<void>.delayed(latency);
    return _backend.addRule(
      AvailabilityRule(
        id: 'ar-${DateTime.now().millisecondsSinceEpoch}',
        weekday: weekday,
        start: start,
        end: end,
        mode: mode,
        slotMinutes: slotMinutes,
      ),
    );
  }

  @override
  Future<void> deleteRule(String id) async {
    await Future<void>.delayed(latency);
    _backend.deleteRule(id);
  }

  @override
  Future<AvailabilityRule> toggleRule(String id, {required bool active}) async {
    await Future<void>.delayed(latency);
    return _backend.toggleRule(id, active: active);
  }

  /// Blocks a day.
  ///
  /// The block is honoured by slot generation, so a patient booking with this
  /// doctor genuinely sees nothing on that date — which is the whole reason a
  /// doctor would tap it.
  @override
  Future<AvailabilityException> blockDay(DateTime date,
      {String? reason}) async {
    await Future<void>.delayed(latency);
    return _backend.blockDay(
      AvailabilityException(
        id: 'ax-${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime(date.year, date.month, date.day),
        isBlocked: true,
        reason: reason,
      ),
    );
  }

  @override
  Future<void> deleteException(String id) async {
    await Future<void>.delayed(latency);
    _backend.deleteException(id);
  }
}
