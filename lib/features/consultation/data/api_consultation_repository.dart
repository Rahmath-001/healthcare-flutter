import 'dart:async';

import '../../../core/network/api_client.dart';
import '../domain/consent_text.dart';
import '../domain/consultation.dart';
import 'consultation_repository.dart';
import 'telehealth_provider.dart';

/// Consultations against the MiDoctor API.
///
/// Media is not here. Room lifecycle, tracks and participant events live behind
/// [TelehealthProvider]; this is the domain half — who may join, whether consent
/// exists, chat, and the lifecycle transitions that outlive the call.
class ApiConsultationRepository implements ConsultationRepository {
  ApiConsultationRepository(this._api, {required this.currentUserId});

  final ApiClient _api;

  /// Needed to decide which chat messages are the caller's own. The server
  /// sends a sender id rather than an `isFromMe` flag, because the same message
  /// is "mine" to one participant and not to the other.
  final String currentUserId;

  Consultation _parse(Map<String, dynamic> json) =>
      Consultation.fromJson(json, myUserId: currentUserId);

  @override
  Future<Consultation> byId(String id) async {
    return _parse(
        await _api.get<Map<String, dynamic>>('/v1/consultations/$id'));
  }

  @override
  Future<Consultation> captureConsent(String id) async {
    // The exact text agreed to is sent so the server can hash and store it.
    // Recording only that consent *happened* proves nothing afterwards — the
    // evidentiary value is being able to show which words were on screen, which
    // is also why this copy is deliberately never machine-translated.
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/consultations/$id/consent',
      body: {
        'consentText': TelemedicineConsent.text,
        'consentVersion': TelemedicineConsent.version,
        'locale': TelemedicineConsent.locale,
      },
    );
    return _parse(json);
  }

  /// Marks the consultation joined on the domain side.
  ///
  /// The media join is a separate call through [TelehealthProvider], which
  /// fetches its own token. Both are needed: this one moves the appointment to
  /// IN_PROGRESS and is what a doctor's "Today" list reads.
  @override
  Future<Consultation> join(String id) => byId(id);

  @override
  Future<Consultation> end(String id) async {
    return _parse(
      await _api.post<Map<String, dynamic>>('/v1/consultations/$id/end'),
    );
  }

  @override
  Future<Consultation> switchToAudio(String id) async {
    return _parse(
      await _api.post<Map<String, dynamic>>('/v1/consultations/$id/audio'),
    );
  }

  @override
  Future<Consultation> sendMessage(String id, String body) async {
    return _parse(
      await _api.post<Map<String, dynamic>>(
        '/v1/consultations/$id/messages',
        body: {'body': body},
      ),
    );
  }

  /// Connection quality is a property of the media session, not of the API.
  ///
  /// The vendor SDK reports it; polling the server for it would be inventing a
  /// number. This yields nothing and lets [TelehealthProvider] be the source.
  @override
  Stream<NetworkQuality> networkQuality(String id) => const Stream.empty();
}
