import 'package:flutter/foundation.dart';

/// Ticket lifecycle, exactly as FR-CS-001 specifies.
enum TicketStatus {
  open('OPEN'),
  assigned('ASSIGNED'),
  escalated('ESCALATED'),
  closed('CLOSED');

  const TicketStatus(this.wire);

  final String wire;

  static TicketStatus fromWire(String? wire) => TicketStatus.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => TicketStatus.open,
      );

  String get label => switch (this) {
        TicketStatus.open => 'Open',
        TicketStatus.assigned => 'Assigned',
        TicketStatus.escalated => 'Escalated',
        TicketStatus.closed => 'Closed',
      };
}

enum TicketCategory {
  loginProblem('LOGIN_PROBLEM'),
  bookingProblem('BOOKING_PROBLEM'),
  paymentProblem('PAYMENT_PROBLEM'),
  recordsProblem('RECORDS_PROBLEM'),
  doctorConcern('DOCTOR_CONCERN'),
  other('OTHER');

  const TicketCategory(this.wire);

  final String wire;

  static TicketCategory fromWire(String? wire) =>
      TicketCategory.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => TicketCategory.other,
      );

  String get label => switch (this) {
        TicketCategory.loginProblem => 'Trouble signing in',
        TicketCategory.bookingProblem => 'Problem with an appointment',
        TicketCategory.paymentProblem => 'Payment or refund',
        TicketCategory.recordsProblem => 'Medical records',
        TicketCategory.doctorConcern => 'Concern about a doctor',
        TicketCategory.other => 'Something else',
      };
}

@immutable
class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.isFromSupport,
    required this.authorName,
  });

  final String id;
  final String body;
  final DateTime sentAt;
  final bool isFromSupport;
  final String authorName;

  factory TicketMessage.fromJson(Map<String, dynamic> json) => TicketMessage(
        id: json['id'] as String,
        body: json['body'] as String,
        sentAt: DateTime.parse(json['at'] as String).toLocal(),
        isFromSupport: json['fromSupport'] as bool? ?? false,
        authorName: json['authorName'] as String? ?? 'Support',
      );
}

/// A support ticket as its owner sees it.
///
/// FR-CS-002 requires internal notes; those have `visibility = INTERNAL_NOTE`
/// server-side and are never included in this model. There is deliberately no
/// client-side flag to filter on — the API simply does not send them, so a UI
/// bug cannot expose an internal note to a patient.
@immutable
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.reference,
    required this.subject,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  final String id;
  final String reference;
  final String subject;
  final TicketCategory category;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TicketMessage> messages;

  SupportTicket copyWith({
    TicketStatus? status,
    DateTime? updatedAt,
    List<TicketMessage>? messages,
  }) =>
      SupportTicket(
        id: id,
        reference: reference,
        subject: subject,
        category: category,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        id: json['id'] as String,
        reference: json['reference'] as String,
        subject: json['subject'] as String,
        category: TicketCategory.fromWire(json['category'] as String?),
        status: TicketStatus.fromWire(json['status'] as String?),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
        messages: ((json['messages'] as List<dynamic>?) ?? const [])
            .map((e) => TicketMessage.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  bool get isOpen => status != TicketStatus.closed;
}
