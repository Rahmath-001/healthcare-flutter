import 'package:flutter/foundation.dart';

import '../../providers_search/domain/doctor.dart';

/// Appointment lifecycle.
///
/// `pendingPayment` exists in the enum but is never entered while payments are
/// deferred: `BookingPolicy.requiresPayment` is false, so a held slot goes
/// straight to `confirmed`. Turning payments on later inserts that one state
/// and changes nothing else.
enum AppointmentStatus {
  held,
  pendingPayment,
  confirmed,
  checkedIn,
  inProgress,
  completed,
  cancelledByPatient,
  cancelledByProvider,
  rescheduled,
  noShowPatient,
  noShowProvider,
  expired;

  bool get isUpcoming =>
      this == AppointmentStatus.confirmed ||
      this == AppointmentStatus.checkedIn ||
      this == AppointmentStatus.pendingPayment;

  bool get isCancelled =>
      this == AppointmentStatus.cancelledByPatient ||
      this == AppointmentStatus.cancelledByProvider ||
      this == AppointmentStatus.expired;

  bool get isPast =>
      this == AppointmentStatus.completed ||
      this == AppointmentStatus.noShowPatient ||
      this == AppointmentStatus.noShowProvider;

  static AppointmentStatus fromWire(String? raw) =>
      switch (raw?.toUpperCase()) {
        'HELD' => AppointmentStatus.held,
        'PENDING_PAYMENT' => AppointmentStatus.pendingPayment,
        'CHECKED_IN' => AppointmentStatus.checkedIn,
        'IN_PROGRESS' => AppointmentStatus.inProgress,
        'COMPLETED' => AppointmentStatus.completed,
        'CANCELLED_BY_PATIENT' => AppointmentStatus.cancelledByPatient,
        'CANCELLED_BY_PROVIDER' => AppointmentStatus.cancelledByProvider,
        'RESCHEDULED' => AppointmentStatus.rescheduled,
        'NO_SHOW_PATIENT' => AppointmentStatus.noShowPatient,
        'NO_SHOW_PROVIDER' => AppointmentStatus.noShowProvider,
        'EXPIRED' => AppointmentStatus.expired,
        _ => AppointmentStatus.confirmed,
      };

  /// The wire value, so a status can be written back out as well as read in.
  ///
  /// Needed by the offline cache, which round-trips a list through exactly the
  /// same `fromJson` the API response uses — a second, private serialisation
  /// would be a second parser to keep in step, and the cached one is the one
  /// nobody notices has drifted.
  String get wire => switch (this) {
        AppointmentStatus.held => 'HELD',
        AppointmentStatus.pendingPayment => 'PENDING_PAYMENT',
        AppointmentStatus.confirmed => 'CONFIRMED',
        AppointmentStatus.checkedIn => 'CHECKED_IN',
        AppointmentStatus.inProgress => 'IN_PROGRESS',
        AppointmentStatus.completed => 'COMPLETED',
        AppointmentStatus.cancelledByPatient => 'CANCELLED_BY_PATIENT',
        AppointmentStatus.cancelledByProvider => 'CANCELLED_BY_PROVIDER',
        AppointmentStatus.rescheduled => 'RESCHEDULED',
        AppointmentStatus.noShowPatient => 'NO_SHOW_PATIENT',
        AppointmentStatus.noShowProvider => 'NO_SHOW_PROVIDER',
        AppointmentStatus.expired => 'EXPIRED',
      };

  String get label => switch (this) {
        AppointmentStatus.held => 'Holding slot',
        AppointmentStatus.pendingPayment => 'Payment pending',
        AppointmentStatus.confirmed => 'Confirmed',
        AppointmentStatus.checkedIn => 'Checked in',
        AppointmentStatus.inProgress => 'In progress',
        AppointmentStatus.completed => 'Completed',
        AppointmentStatus.cancelledByPatient => 'Cancelled by you',
        AppointmentStatus.cancelledByProvider => 'Cancelled by doctor',
        AppointmentStatus.rescheduled => 'Rescheduled',
        AppointmentStatus.noShowPatient => 'Missed',
        AppointmentStatus.noShowProvider => 'Doctor did not join',
        AppointmentStatus.expired => 'Expired',
      };
}

/// Payment state, carried from day one so enabling payments later is a policy
/// change rather than a schema migration.
enum PaymentStatus {
  notRequired,
  pending,
  authorized,
  paid,
  refundPending,
  refunded,
  failed;

  String get wire => switch (this) {
        PaymentStatus.notRequired => 'NOT_REQUIRED',
        PaymentStatus.pending => 'PENDING',
        PaymentStatus.authorized => 'AUTHORIZED',
        PaymentStatus.paid => 'PAID',
        PaymentStatus.refundPending => 'REFUND_PENDING',
        PaymentStatus.refunded => 'REFUNDED',
        PaymentStatus.failed => 'FAILED',
      };

  String get label => switch (this) {
        PaymentStatus.notRequired => 'No payment required',
        PaymentStatus.pending => 'Payment pending',
        PaymentStatus.authorized => 'Payment authorized',
        PaymentStatus.paid => 'Paid',
        PaymentStatus.refundPending => 'Refund in progress',
        PaymentStatus.refunded => 'Refunded',
        PaymentStatus.failed => 'Payment failed',
      };

  static PaymentStatus fromWire(String? raw) => switch (raw?.toUpperCase()) {
        'PENDING' => PaymentStatus.pending,
        'AUTHORIZED' => PaymentStatus.authorized,
        'PAID' => PaymentStatus.paid,
        'REFUND_PENDING' => PaymentStatus.refundPending,
        'REFUNDED' => PaymentStatus.refunded,
        'FAILED' => PaymentStatus.failed,
        _ => PaymentStatus.notRequired,
      };
}

@immutable
class Appointment {
  const Appointment({
    required this.id,
    required this.referenceCode,
    required this.doctor,
    required this.patientName,
    required this.start,
    required this.end,
    required this.mode,
    required this.status,
    required this.paymentStatus,
    required this.feeInr,
    this.reasonForVisit,
    this.cancellationReason,
    this.consultationId,
    this.hasPrescription = false,
    this.hasRating = false,
  });

  final String id;

  /// Human-readable code the patient can quote to support, e.g. MD-8K2P4Q.
  final String referenceCode;

  final Doctor doctor;
  final String patientName;
  final DateTime start;
  final DateTime end;
  final ConsultationMode mode;
  final AppointmentStatus status;
  final PaymentStatus paymentStatus;
  final int feeInr;
  final String? reasonForVisit;
  final String? cancellationReason;
  final String? consultationId;
  final bool hasPrescription;
  final bool hasRating;

  Duration get duration => end.difference(start);

  /// Free cancellation window. Provisional policy: the spec defines none, so
  /// this is one place to change once the business decides.
  static const freeCancellationWindow = Duration(hours: 24);

  bool get canCancel => status.isUpcoming && DateTime.now().isBefore(start);

  bool get isFreeCancellation =>
      start.difference(DateTime.now()) >= freeCancellationWindow;

  bool get canReschedule => canCancel;

  /// The join window matches the server's token-minting rule: 15 minutes before
  /// the start, up to 30 minutes after the scheduled end.
  bool get canJoinConsultation {
    if (mode == ConsultationMode.inPerson) return false;
    if (!status.isUpcoming && status != AppointmentStatus.inProgress) {
      return false;
    }
    final now = DateTime.now();
    return now.isAfter(start.subtract(const Duration(minutes: 15))) &&
        now.isBefore(end.add(const Duration(minutes: 30)));
  }

  bool get canRate => status == AppointmentStatus.completed && !hasRating;

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] as String,
        referenceCode: json['referenceCode'] as String? ?? '',
        doctor: Doctor.fromJson(json['doctor'] as Map<String, dynamic>),
        patientName: json['patientName'] as String? ?? '',
        start: DateTime.parse(json['start'] as String).toLocal(),
        end: DateTime.parse(json['end'] as String).toLocal(),
        mode: ConsultationMode.fromWire(json['mode'] as String?),
        status: AppointmentStatus.fromWire(json['status'] as String?),
        paymentStatus: PaymentStatus.fromWire(json['paymentStatus'] as String?),
        feeInr: (json['feeInr'] as num?)?.toInt() ?? 0,
        reasonForVisit: json['reasonForVisit'] as String?,
        cancellationReason: json['cancellationReason'] as String?,
        consultationId: json['consultationId'] as String?,
        hasPrescription: json['hasPrescription'] as bool? ?? false,
        hasRating: json['hasRating'] as bool? ?? false,
      );

  Appointment copyWith({
    AppointmentStatus? status,
    PaymentStatus? paymentStatus,
    String? cancellationReason,
    bool? hasRating,
    bool? hasPrescription,
    DateTime? start,
    DateTime? end,
  }) =>
      Appointment(
        id: id,
        referenceCode: referenceCode,
        doctor: doctor,
        patientName: patientName,
        // The reference code deliberately survives a reschedule: it is what the
        // patient quoted to the clinic and what the confirmation email says.
        start: start ?? this.start,
        end: end ?? this.end,
        mode: mode,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        feeInr: feeInr,
        reasonForVisit: reasonForVisit,
        cancellationReason: cancellationReason ?? this.cancellationReason,
        consultationId: consultationId,
        hasPrescription: hasPrescription ?? this.hasPrescription,
        hasRating: hasRating ?? this.hasRating,
      );
}

/// A bookable slot, materialised server-side for a rolling window.
@immutable
class AppointmentSlot {
  const AppointmentSlot({
    required this.id,
    required this.start,
    required this.end,
    required this.mode,
    this.isAvailable = true,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final ConsultationMode mode;
  final bool isAvailable;

  factory AppointmentSlot.fromJson(Map<String, dynamic> json) =>
      AppointmentSlot(
        id: json['id'] as String,
        start: DateTime.parse(json['start'] as String).toLocal(),
        end: DateTime.parse(json['end'] as String).toLocal(),
        mode: ConsultationMode.fromWire(json['mode'] as String?),
        isAvailable: json['isAvailable'] as bool? ?? true,
      );
}

/// A short-lived reservation taken while the patient confirms.
///
/// Without this, "prevent double booking" and "payment required" fight each
/// other: the patient either pays for a slot someone else takes, or holds a
/// slot forever without paying.
@immutable
class SlotHold {
  const SlotHold({
    required this.slotId,
    required this.expiresAt,
  });

  final String slotId;
  final DateTime expiresAt;

  static const duration = Duration(minutes: 10);

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isExpired => remaining == Duration.zero;

  factory SlotHold.fromJson(Map<String, dynamic> json) => SlotHold(
        slotId: json['slotId'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
      );
}
