import 'package:flutter/foundation.dart';

import '../../providers_search/domain/doctor.dart';

enum ConsultationStatus {
  scheduled('SCHEDULED'),
  waiting('WAITING'),
  active('ACTIVE'),
  ended('ENDED'),
  abandoned('ABANDONED'),
  techFailed('TECH_FAILED');

  const ConsultationStatus(this.wire);

  final String wire;

  static ConsultationStatus fromWire(String? wire) =>
      ConsultationStatus.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => ConsultationStatus.scheduled,
      );

  String get label => switch (this) {
        ConsultationStatus.scheduled => 'Scheduled',
        ConsultationStatus.waiting => 'Waiting room',
        ConsultationStatus.active => 'In progress',
        ConsultationStatus.ended => 'Ended',
        ConsultationStatus.abandoned => 'Not completed',
        ConsultationStatus.techFailed => 'Connection failed',
      };
}

/// Reported connection quality, used to decide when to suggest dropping to
/// audio. Indian mobile networks make this a core flow, not an edge case.
enum NetworkQuality {
  good,
  fair,
  poor;

  String get label => switch (this) {
        NetworkQuality.good => 'Good connection',
        NetworkQuality.fair => 'Unstable connection',
        NetworkQuality.poor => 'Poor connection',
      };
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.isFromMe,
    required this.senderName,
  });

  final String id;
  final String body;
  final DateTime sentAt;
  final bool isFromMe;
  final String senderName;

  factory ChatMessage.fromJson(Map<String, dynamic> json, String myUserId) =>
      ChatMessage(
        id: json['id'] as String,
        body: json['body'] as String,
        sentAt: DateTime.parse(json['sentAt'] as String).toLocal(),
        // Resolved against the caller rather than sent as a flag: the same
        // message is "mine" to one participant and not to the other.
        isFromMe: json['senderId'] == myUserId,
        senderName: json['senderName'] as String? ?? 'Participant',
      );
}

/// A live or completed consultation.
///
/// [isRecorded] is deliberately a hard-coded false rather than a nullable flag:
/// FR-TEL-003 forbids recording, and the database enforces it with a CHECK
/// constraint. Nothing in the client can turn it on.
@immutable
class Consultation {
  const Consultation({
    required this.id,
    required this.appointmentId,
    required this.doctor,
    required this.patientName,
    required this.mode,
    required this.status,
    required this.scheduledStart,
    this.startedAt,
    this.endedAt,
    this.messages = const [],
    this.networkQuality = NetworkQuality.good,
    this.consentCapturedAt,
  });

  final String id;
  final String appointmentId;
  final Doctor doctor;
  final String patientName;
  final ConsultationMode mode;
  final ConsultationStatus status;
  final DateTime scheduledStart;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<ChatMessage> messages;
  final NetworkQuality networkQuality;

  /// Telemedicine consent must be captured before connecting — an explicit
  /// requirement of the Telemedicine Practice Guidelines.
  final DateTime? consentCapturedAt;

  factory Consultation.fromJson(
    Map<String, dynamic> json, {
    required String myUserId,
  }) =>
      Consultation(
        id: json['id'] as String,
        appointmentId: json['appointmentId'] as String,
        doctor: Doctor.fromJson(json['doctor'] as Map<String, dynamic>),
        patientName: json['patientName'] as String? ?? 'Patient',
        mode: ConsultationMode.fromWire(json['mode'] as String?),
        status: ConsultationStatus.fromWire(json['status'] as String?),
        scheduledStart:
            DateTime.parse(json['scheduledStart'] as String).toLocal(),
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.parse(json['startedAt'] as String).toLocal(),
        endedAt: json['endedAt'] == null
            ? null
            : DateTime.parse(json['endedAt'] as String).toLocal(),
        messages: ((json['messages'] as List<dynamic>?) ?? const [])
            .map((e) =>
                ChatMessage.fromJson(e as Map<String, dynamic>, myUserId))
            .toList(growable: false),
        consentCapturedAt: json['consentCapturedAt'] == null
            ? null
            : DateTime.parse(json['consentCapturedAt'] as String).toLocal(),
      );

  /// Never true. Present so the UI can state it plainly to both parties.
  bool get isRecorded => false;

  bool get hasConsent => consentCapturedAt != null;

  /// FR-TEL-002: start, end and duration are stored for every consultation.
  Duration? get duration {
    final s = startedAt;
    final e = endedAt;
    if (s == null) return null;
    return (e ?? DateTime.now()).difference(s);
  }

  Consultation copyWith({
    ConsultationStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    List<ChatMessage>? messages,
    NetworkQuality? networkQuality,
    DateTime? consentCapturedAt,
    ConsultationMode? mode,
  }) =>
      Consultation(
        id: id,
        appointmentId: appointmentId,
        doctor: doctor,
        patientName: patientName,
        mode: mode ?? this.mode,
        status: status ?? this.status,
        scheduledStart: scheduledStart,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        messages: messages ?? this.messages,
        networkQuality: networkQuality ?? this.networkQuality,
        consentCapturedAt: consentCapturedAt ?? this.consentCapturedAt,
      );
}
