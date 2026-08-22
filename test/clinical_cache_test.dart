import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/error/failure.dart';
import 'package:healthcare_mobile/core/storage/clinical_cache.dart';
import 'package:healthcare_mobile/features/appointments/data/appointment_repository.dart';
import 'package:healthcare_mobile/features/appointments/data/cached_appointment_repository.dart';
import 'package:healthcare_mobile/features/appointments/domain/appointment.dart';
import 'package:healthcare_mobile/features/appointments/domain/queue_position.dart';
import 'package:healthcare_mobile/features/providers_search/data/doctor_fixtures.dart';
import 'package:healthcare_mobile/features/providers_search/domain/doctor.dart';

/// The offline copy.
///
/// This is the feature that reversed a standing rule — clinical data on the
/// device — so the tests are about the conditions that make the trade
/// acceptable rather than about it merely working: it must expire, it must not
/// mask a real refusal, and it must announce itself.
void main() {
  Appointment appointment(String id, {AppointmentStatus? status}) {
    final start = DateTime(2026, 9, 1, 10);
    return Appointment(
      id: id,
      referenceCode: 'MD$id',
      doctor: DoctorFixtures.byId('d1'),
      patientName: 'Priya Sharma',
      start: start,
      end: start.add(const Duration(minutes: 30)),
      mode: ConsultationMode.video,
      status: status ?? AppointmentStatus.confirmed,
      paymentStatus: PaymentStatus.notRequired,
      feeInr: 800,
      reasonForVisit: 'Follow-up',
    );
  }

  late _MemoryCache cache;
  late _FakeStatus status;
  late _StubRepository inner;

  setUp(() {
    cache = _MemoryCache();
    status = _FakeStatus();
    inner = _StubRepository();
  });

  CachedAppointmentRepository build({required bool online}) =>
      CachedAppointmentRepository(
        inner: inner,
        cache: cache,
        status: status,
        isOnline: () async => online,
      );

  test('a successful fetch is stored and reported as live', () async {
    inner.appointments = [appointment('a1')];
    final repo = build(online: true);

    final result = await repo.listForPatient();

    expect(result.single.id, 'a1');
    expect(cache.entries, contains(CacheKeys.patientAppointments));
    expect(status.fromCache, isEmpty);
  });

  test('offline serves the stored copy without a doomed request', () async {
    inner.appointments = [appointment('a1')];
    await build(online: true).listForPatient();

    inner.calls = 0;
    final result = await build(online: false).listForPatient();

    expect(result.single.id, 'a1');
    // A request that cannot succeed is a spinner that resolves into an error
    // thirty seconds later.
    expect(inner.calls, 0);
    expect(status.fromCache[CacheKeys.patientAppointments], isNotNull);
  });

  test('a round trip preserves what the screen renders', () async {
    // The cache serialises to the wire shape and parses with the same
    // `fromJson` the API response uses. A private format would be a second
    // parser to keep in step, and this is the assertion that would catch it
    // drifting.
    inner.appointments = [
      appointment('a1', status: AppointmentStatus.checkedIn),
    ];
    await build(online: true).listForPatient();

    final restored = (await build(online: false).listForPatient()).single;
    final original = inner.appointments.single;

    expect(restored.id, original.id);
    expect(restored.referenceCode, original.referenceCode);
    expect(restored.start, original.start);
    expect(restored.end, original.end);
    expect(restored.mode, original.mode);
    expect(restored.status, original.status);
    expect(restored.paymentStatus, original.paymentStatus);
    expect(restored.feeInr, original.feeInr);
    expect(restored.reasonForVisit, original.reasonForVisit);
    expect(restored.doctor.name, original.doctor.name);
  });

  test('a network failure falls back to the copy', () async {
    // The common Indian case: a connection that exists and does not work.
    inner.appointments = [appointment('a1')];
    await build(online: true).listForPatient();

    inner.error = const Failure(
      kind: FailureKind.network,
      message: 'No connection.',
    );
    final result = await build(online: true).listForPatient();

    expect(result.single.id, 'a1');
    expect(status.fromCache[CacheKeys.patientAppointments], isNotNull);
  });

  test('a refusal is not masked by the copy', () async {
    // A 403 is an answer. Serving last week's list instead would hide a real
    // authorization change — a suspended account still showing its
    // appointments is the exact failure the session design exists to prevent.
    inner.appointments = [appointment('a1')];
    await build(online: true).listForPatient();

    inner.error = const Failure(
      kind: FailureKind.forbidden,
      message: 'This account is not active.',
      code: 'ACCOUNT_NOT_ACTIVE',
    );

    await expectLater(
      build(online: true).listForPatient(),
      throwsA(
          isA<Failure>().having((f) => f.kind, 'kind', FailureKind.forbidden)),
    );
  });

  test('an expired copy is not served, and is dropped', () async {
    inner.appointments = [appointment('a1')];
    await build(online: true).listForPatient();

    // Older than the window. A clinical list from last week presented as
    // today's plan is worse than no list.
    cache.age = ClinicalCache.maxAge + const Duration(minutes: 1);

    inner.error = const Failure(
      kind: FailureKind.network,
      message: 'No connection.',
    );
    await expectLater(
      build(online: true).listForPatient(),
      throwsA(isA<Failure>()),
    );
    expect(cache.entries, isEmpty, reason: 'the stale entry is deleted');
  });

  test('wiping removes everything', () async {
    inner.appointments = [appointment('a1')];
    await build(online: true).listForPatient();
    expect(cache.entries, isNotEmpty);

    await cache.wipe();
    expect(cache.entries, isEmpty);
  });

  test('the provider list is never cached', () async {
    // A doctor's day is other people's clinical data, on a device that may be
    // shared around a clinic.
    inner.appointments = [appointment('a1')];
    await build(online: true).listForProvider();

    expect(cache.entries, isEmpty);
  });

  test('mutations are never served from the copy', () async {
    // Booking, cancelling and moving all need the server to arbitrate. An
    // offline "success" would be a lie the user acts on.
    inner.error = const Failure(
      kind: FailureKind.network,
      message: 'No connection.',
    );
    final repo = build(online: false);

    await expectLater(
      repo.cancel('a1', reason: 'x'),
      throwsA(isA<Failure>()),
    );
    await expectLater(
      repo.queuePosition('a1'),
      throwsA(isA<Failure>()),
    );
  });
}

/// An in-memory stand-in for the secure store, with a settable age so expiry
/// can be tested without waiting twelve hours.
class _MemoryCache implements ClinicalCache {
  final Map<String, Object> entries = {};
  Duration age = Duration.zero;

  @override
  bool get isSupported => true;

  @override
  Future<void> write(String key, Object json) async {
    entries[key] = json;
  }

  @override
  Future<({Object data, DateTime cachedAt})?> read(String key) async {
    final value = entries[key];
    if (value == null) return null;
    if (age > ClinicalCache.maxAge) {
      entries.remove(key);
      return null;
    }
    return (data: value, cachedAt: DateTime.now().subtract(age));
  }

  @override
  Future<void> wipe() async => entries.clear();
}

class _FakeStatus implements OfflineCacheStatus {
  final Map<String, DateTime> fromCache = {};

  @override
  void servedFromCache(String key, DateTime cachedAt) =>
      fromCache[key] = cachedAt;

  @override
  void servedLive(String key) => fromCache.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubRepository implements AppointmentRepository {
  List<Appointment> appointments = [];
  Failure? error;
  int calls = 0;

  @override
  Future<List<Appointment>> listForPatient() async {
    calls++;
    if (error != null) throw error!;
    return appointments;
  }

  @override
  Future<List<Appointment>> listForProvider() async {
    calls++;
    if (error != null) throw error!;
    return appointments;
  }

  @override
  Future<Appointment> byId(String id) async => throw error ?? _unimplemented;

  @override
  Future<Appointment> cancel(String id, {required String reason}) async =>
      throw error ?? _unimplemented;

  @override
  Future<Appointment> reschedule(
    String id, {
    required DateTime start,
    required DateTime end,
  }) async =>
      throw error ?? _unimplemented;

  @override
  Future<Appointment> checkIn(String id) async => throw error ?? _unimplemented;

  @override
  Future<QueuePosition> queuePosition(String id) async =>
      throw error ?? _unimplemented;

  static const _unimplemented = Failure(
    kind: FailureKind.unknown,
    message: 'not used in this test',
  );
}
