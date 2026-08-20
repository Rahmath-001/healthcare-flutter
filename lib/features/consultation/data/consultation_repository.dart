import 'dart:async';

import '../../../core/error/failure.dart';
import '../../providers_search/data/doctor_fixtures.dart';
import '../../providers_search/domain/doctor.dart';
import '../domain/consultation.dart';

/// Consultation lifecycle and chat relay.
///
/// The real implementation sits behind a `TelehealthProvider` seam so the
/// media vendor (100ms first) can be swapped without touching this interface:
/// mint a join token, drive room lifecycle, surface participant events. That is
/// the whole vendor surface.
abstract class ConsultationRepository {
  Future<Consultation> byId(String id);

  /// Records telemedicine consent. Required before connecting, per the
  /// Telemedicine Practice Guidelines.
  Future<Consultation> captureConsent(String id);

  /// Joins the room. The server only mints a token when the appointment is
  /// confirmed, the caller is a participant, the provider is approved, and
  /// consent exists — so this can fail for reasons the UI must explain.
  Future<Consultation> join(String id);

  Future<Consultation> end(String id);

  /// Drops from video to audio without leaving the consultation. Not a
  /// nicety — on Indian mobile networks it is what keeps a call alive.
  Future<Consultation> switchToAudio(String id);

  Future<Consultation> sendMessage(String id, String body);

  /// Emits connection-quality changes so the UI can prompt an audio fallback.
  Stream<NetworkQuality> networkQuality(String id);
}

class FixtureConsultationRepository implements ConsultationRepository {
  FixtureConsultationRepository({
    this.latency = const Duration(milliseconds: 400),
  }) {
    _seed();
  }

  final Duration latency;
  final Map<String, Consultation> _consultations = {};

  void _seed() {
    final now = DateTime.now();
    _consultations['c1'] = Consultation(
      id: 'c1',
      appointmentId: 'a1',
      doctor: DoctorFixtures.byId('d1'),
      patientName: 'You',
      mode: ConsultationMode.video,
      status: ConsultationStatus.scheduled,
      scheduledStart: now.subtract(const Duration(minutes: 5)),
    );
    _consultations['c3'] = Consultation(
      id: 'c3',
      appointmentId: 'a3',
      doctor: DoctorFixtures.byId('d3'),
      patientName: 'You',
      mode: ConsultationMode.video,
      status: ConsultationStatus.ended,
      scheduledStart: now.subtract(const Duration(days: 9)),
      startedAt: now.subtract(const Duration(days: 9)),
      endedAt: now.subtract(const Duration(days: 9)).add(
            const Duration(minutes: 18),
          ),
      consentCapturedAt: now.subtract(const Duration(days: 9)),
    );
  }

  Consultation _require(String id) {
    final c = _consultations[id];
    if (c == null) {
      throw const Failure(
        kind: FailureKind.notFound,
        message: 'This consultation is no longer available.',
        code: 'CONSULTATION_NOT_FOUND',
      );
    }
    return c;
  }

  @override
  Future<Consultation> byId(String id) async {
    await Future<void>.delayed(latency);
    return _require(id);
  }

  @override
  Future<Consultation> captureConsent(String id) async {
    await Future<void>.delayed(latency);
    final updated = _require(id).copyWith(consentCapturedAt: DateTime.now());
    _consultations[id] = updated;
    return updated;
  }

  @override
  Future<Consultation> join(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final current = _require(id);

    if (!current.hasConsent) {
      throw const Failure(
        kind: FailureKind.forbidden,
        message: 'Consent is required before the consultation can start.',
        code: 'CONSENT_REQUIRED',
      );
    }

    final updated = current.copyWith(
      status: ConsultationStatus.active,
      startedAt: current.startedAt ?? DateTime.now(),
    );
    _consultations[id] = updated;
    return updated;
  }

  @override
  Future<Consultation> end(String id) async {
    await Future<void>.delayed(latency);
    final updated = _require(id).copyWith(
      status: ConsultationStatus.ended,
      endedAt: DateTime.now(),
    );
    _consultations[id] = updated;
    return updated;
  }

  @override
  Future<Consultation> switchToAudio(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final updated = _require(id).copyWith(mode: ConsultationMode.audio);
    _consultations[id] = updated;
    return updated;
  }

  @override
  Future<Consultation> sendMessage(String id, String body) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final current = _require(id);
    final now = DateTime.now();

    final mine = ChatMessage(
      id: 'm-${now.millisecondsSinceEpoch}',
      body: body.trim(),
      sentAt: now,
      isFromMe: true,
      senderName: 'You',
    );

    final updated = current.copyWith(messages: [...current.messages, mine]);
    _consultations[id] = updated;
    return updated;
  }

  @override
  Stream<NetworkQuality> networkQuality(String id) async* {
    // Deliberately degrades: the audio-fallback path is a primary flow here,
    // not an edge case, so it needs to be reachable while developing.
    yield NetworkQuality.good;
    await Future<void>.delayed(const Duration(seconds: 12));
    yield NetworkQuality.fair;
    await Future<void>.delayed(const Duration(seconds: 10));
    yield NetworkQuality.poor;
  }
}
