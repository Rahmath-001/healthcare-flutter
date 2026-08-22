import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/storage/clinical_cache.dart';
import '../domain/prescription.dart';
import '../domain/refill_request.dart';
import 'prescription_repository.dart';

/// Adds an offline copy of the patient's prescription list.
///
/// The most defensible thing in this app to hold on a device. A patient at a
/// pharmacy counter with no signal is the exact person who needs to see what
/// they were prescribed, and it is the one list where being unable to open the
/// app has an immediate physical consequence.
///
/// **Metadata only, and that boundary is the whole safety argument.** The
/// summary is cached — drug names, dosages, the issuing doctor, the
/// verification code. The **PDF is not**: it is a signed-URL download of a
/// write-once document, and copying it to the device would put the legal
/// artifact somewhere it can be read without authentication and cannot be
/// revoked. `officialPdf` therefore stays live and fails offline, which is
/// correct — the local renderer already exists as the offline fallback.
class CachedPrescriptionRepository implements PrescriptionRepository {
  CachedPrescriptionRepository({
    required PrescriptionRepository inner,
    required ClinicalCache cache,
    required OfflineCacheStatus status,
    required Future<bool> Function() isOnline,
  })  : _inner = inner,
        _cache = cache,
        _status = status,
        _isOnline = isOnline;

  final PrescriptionRepository _inner;
  final ClinicalCache _cache;
  final OfflineCacheStatus _status;
  final Future<bool> Function() _isOnline;

  static const _key = CacheKeys.prescriptions;

  @override
  Future<List<Prescription>> listForPatient() async {
    if (!await _isOnline()) {
      final cached = await _readCache();
      if (cached != null) return cached;
      return _inner.listForPatient();
    }

    try {
      final fresh = await _inner.listForPatient();
      // Not awaited: storing the copy is housekeeping, and nobody should wait
      // on a keychain write to read their own prescriptions.
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

  Future<List<Prescription>?> _readCache() async {
    final entry = await _cache.read(_key);
    if (entry == null) return null;

    final list = (entry.data as List<dynamic>)
        .map((e) => Prescription.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    _status.servedFromCache(_key, entry.cachedAt);
    return list;
  }

  /// The wire shape, so the cached copy parses through the same `fromJson` the
  /// API response does rather than through a second, quietly drifting parser.
  static Map<String, dynamic> _toJson(Prescription p) => {
        'id': p.id,
        'verificationCode': p.verificationCode,
        'providerName': p.providerName,
        'providerQualification': p.providerQualification,
        'providerRegistrationNumber': p.providerRegistrationNumber,
        'patientName': p.patientName,
        'patientAge': p.patientAge,
        'patientGender': p.patientGender,
        'issuedAt': p.issuedAt.toUtc().toIso8601String(),
        'status': p.status.wire,
        'diagnosis': p.diagnosis,
        'advice': p.advice,
        'followUpDate': p.followUpDate?.toUtc().toIso8601String(),
        'appointmentReference': p.appointmentReference,
        'items': p.items
            .map((i) => {
                  'drugName': i.drugName,
                  'genericName': i.genericName,
                  'strength': i.strength,
                  'form': i.form,
                  'frequency': i.frequency,
                  'durationDays': i.durationDays,
                  'instructions': i.instructions,
                })
            .toList(),
      };

  // Live only. A prescription's PDF is a signed download of a write-once
  // document and is deliberately never copied to the device; a refill is a
  // request the server has to arbitrate; the drug catalogue is a search.

  @override
  Future<Prescription> byId(String id) => _inner.byId(id);

  @override
  Future<List<Drug>> searchDrugs(String query) => _inner.searchDrugs(query);

  @override
  Future<Prescription> issue({
    required String appointmentId,
    required String patientName,
    required String patientAge,
    required String patientGender,
    required List<PrescriptionItem> items,
    required bool isFollowUp,
    String? diagnosis,
    String? advice,
    DateTime? followUpDate,
  }) =>
      _inner.issue(
        appointmentId: appointmentId,
        patientName: patientName,
        patientAge: patientAge,
        patientGender: patientGender,
        items: items,
        isFollowUp: isFollowUp,
        diagnosis: diagnosis,
        advice: advice,
        followUpDate: followUpDate,
      );

  @override
  Future<({String url, String? sha256})?> officialPdf(String id) =>
      _inner.officialPdf(id);

  @override
  Future<List<RefillRequest>> refillRequests() => _inner.refillRequests();

  @override
  Future<RefillRequest> requestRefill(String prescriptionId, {String? note}) =>
      _inner.requestRefill(prescriptionId, note: note);

  @override
  Future<RefillRequest> cancelRefill(String id) => _inner.cancelRefill(id);

  @override
  Future<RefillRequest> approveRefill(String id) => _inner.approveRefill(id);

  @override
  Future<RefillRequest> declineRefill(
    String id, {
    required RefillDeclineReason reason,
    required String note,
  }) =>
      _inner.declineRefill(id, reason: reason, note: note);
}
