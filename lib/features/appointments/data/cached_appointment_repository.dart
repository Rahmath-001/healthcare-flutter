import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/storage/clinical_cache.dart';
import '../domain/appointment.dart';
import '../domain/queue_position.dart';
import 'appointment_repository.dart';

/// Adds an offline copy of the patient's appointment list.
///
/// A decorator rather than a change to either repository, so the caching policy
/// lives in one readable place and both the fixture and the API implementation
/// stay about their own job. It wraps whichever is bound, which is also what
/// makes this testable on sample data: put the phone in flight mode and the
/// fixture is never called either.
///
/// ## What is and is not cached
///
/// **The patient's own appointment list, and nothing else.** Not the provider's
/// list — a doctor's day is other people's clinical data on a device that may
/// be shared in a clinic. Not a single appointment by id, because the only
/// route to that screen is through the list. Not the queue position, which is a
/// live number that is wrong the moment it is stale.
///
/// ## When the cache is used
///
///  * **Offline**: served immediately, without a doomed request first. The
///    alternative is a spinner that resolves into an error the user cannot act
///    on, thirty seconds later.
///  * **Network failure while nominally online**: served as a fallback, which
///    covers the more common Indian case of a connection that exists and does
///    not work.
///  * **Any other failure**: not served. A 403 is an answer, and answering it
///    with last week's data would hide a real authorization change.
class CachedAppointmentRepository implements AppointmentRepository {
  CachedAppointmentRepository({
    required AppointmentRepository inner,
    required ClinicalCache cache,
    required OfflineCacheStatus status,
    required Future<bool> Function() isOnline,
  })  : _inner = inner,
        _cache = cache,
        _status = status,
        _isOnline = isOnline;

  final AppointmentRepository _inner;
  final ClinicalCache _cache;
  final OfflineCacheStatus _status;
  final Future<bool> Function() _isOnline;

  static const _key = CacheKeys.patientAppointments;

  @override
  Future<List<Appointment>> listForPatient() async {
    if (!await _isOnline()) {
      final cached = await _readCache();
      if (cached != null) return cached;
      // No cache and no connection: the ordinary offline failure, which the
      // UI already renders as "you are offline" rather than as a fault.
      return _inner.listForPatient();
    }

    try {
      final fresh = await _inner.listForPatient();
      // Not awaited. Storing the copy is housekeeping; making the patient's
      // list wait on a keychain write would add a disk round trip to the one
      // screen they opened the app for, to no benefit — if the write fails or
      // is slow, the only consequence is a colder cache next time.
      unawaited(_cache.write(_key, fresh.map(_toJson).toList()));
      _status.servedLive(_key);
      return fresh;
    } on Failure catch (f) {
      if (f.kind != FailureKind.network) rethrow;
      final cached = await _readCache();
      if (cached == null) rethrow;
      return cached;
    }
  }

  Future<List<Appointment>?> _readCache() async {
    final entry = await _cache.read(_key);
    if (entry == null) return null;

    final list = (entry.data as List<dynamic>)
        .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    _status.servedFromCache(_key, entry.cachedAt);
    return list;
  }

  /// The wire shape, so a cached list parses through exactly the same
  /// `fromJson` the API response does. Serialising a private format would mean
  /// two parsers to keep in step, and the cached one would be the one nobody
  /// notices has drifted.
  static Map<String, dynamic> _toJson(Appointment a) => {
        'id': a.id,
        'referenceCode': a.referenceCode,
        'doctor': {
          'id': a.doctor.id,
          'name': a.doctor.name,
          'qualification': a.doctor.qualification,
          'registrationNumber': a.doctor.registrationNumber,
          'consultationFeeInr': a.doctor.consultationFeeInr,
          'videoFeeInr': a.doctor.videoFeeInr,
          'rating': a.doctor.rating,
          'ratingCount': a.doctor.ratingCount,
          'hospital': {
            'name': a.doctor.hospital.name,
            'city': a.doctor.hospital.city,
          },
          'specialties': a.doctor.specialties
              .map((s) => {'code': s.code, 'name': s.name})
              .toList(),
          'modes': a.doctor.modes.map((m) => m.wire).toList(),
        },
        'patientName': a.patientName,
        'start': a.start.toUtc().toIso8601String(),
        'end': a.end.toUtc().toIso8601String(),
        'mode': a.mode.wire,
        'status': a.status.wire,
        'paymentStatus': a.paymentStatus.wire,
        'feeInr': a.feeInr,
        'reasonForVisit': a.reasonForVisit,
        'cancellationReason': a.cancellationReason,
        'consultationId': a.consultationId,
        'hasPrescription': a.hasPrescription,
        'hasRating': a.hasRating,
      };

  // Everything below is a live operation. None of it is cached, and none of it
  // is meaningful offline: booking, cancelling and moving an appointment all
  // need the server to arbitrate, and a queue position from an hour ago is a
  // wrong number rather than an old one.

  @override
  Future<List<Appointment>> listForProvider() => _inner.listForProvider();

  @override
  Future<Appointment> byId(String id) => _inner.byId(id);

  @override
  Future<Appointment> cancel(String id, {required String reason}) =>
      _inner.cancel(id, reason: reason);

  @override
  Future<Appointment> reschedule(
    String id, {
    required DateTime start,
    required DateTime end,
  }) =>
      _inner.reschedule(id, start: start, end: end);

  @override
  Future<Appointment> checkIn(String id) => _inner.checkIn(id);

  @override
  Future<QueuePosition> queuePosition(String id) => _inner.queuePosition(id);
}
