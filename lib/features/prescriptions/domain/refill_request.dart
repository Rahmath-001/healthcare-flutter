import 'package:meta/meta.dart';

import 'prescription.dart';

/// Where a refill request has got to.
enum RefillStatus {
  pending('PENDING'),
  approved('APPROVED'),
  declined('DECLINED'),

  /// Withdrawn by the patient before a doctor ruled on it.
  cancelled('CANCELLED');

  const RefillStatus(this.wire);

  final String wire;

  /// Unknown reads as pending, never as approved. The safe direction for
  /// something that ends in a drug being dispensed.
  static RefillStatus fromWire(String? wire) => RefillStatus.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => RefillStatus.pending,
      );

  String get label => switch (this) {
        RefillStatus.pending => 'Awaiting your doctor',
        RefillStatus.approved => 'Approved',
        RefillStatus.declined => 'Declined',
        RefillStatus.cancelled => 'Withdrawn',
      };

  bool get isOpen => this == RefillStatus.pending;
}

/// Why a doctor said no.
///
/// A closed set with a mandatory free-text note rather than free text alone.
/// Two reasons:
///
///  * A patient told only "declined" will request again, or stop taking a
///    medicine they still need. The category tells them what to *do* — book a
///    review, come in, discuss an alternative — and the note tells them why.
///  * Refusals are the decisions most likely to be examined later. A structured
///    reason can be counted and audited; a paragraph cannot.
enum RefillDeclineReason {
  reviewNeeded('REVIEW_NEEDED'),
  notSuitableRemotely('NOT_SUITABLE_REMOTELY'),
  tooSoon('TOO_SOON'),
  treatmentChanged('TREATMENT_CHANGED'),
  seeAnotherDoctor('SEE_ANOTHER_DOCTOR'),
  other('OTHER');

  const RefillDeclineReason(this.wire);

  final String wire;

  static RefillDeclineReason fromWire(String? wire) =>
      RefillDeclineReason.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => RefillDeclineReason.other,
      );

  String get label => switch (this) {
        RefillDeclineReason.reviewNeeded =>
          'You need a review before another course',
        RefillDeclineReason.notSuitableRemotely =>
          'This medicine cannot be repeated remotely',
        RefillDeclineReason.tooSoon => 'Too soon for a repeat',
        RefillDeclineReason.treatmentChanged => 'Your treatment has changed',
        RefillDeclineReason.seeAnotherDoctor =>
          'Please see the doctor who is managing this',
        RefillDeclineReason.other => 'Other',
      };
}

/// A patient asking their doctor to repeat a prescription.
///
/// ## Why this is not just "prescribe again"
///
/// A refill is, by definition, a follow-up — and follow-up status is exactly
/// what makes a List B medicine prescribable at all under the MoHFW
/// telemedicine rules. That makes this the one patient-initiated path that can
/// end in a restricted drug being dispensed, so the request is a *record*
/// rather than a message: who asked, when, which prescription, what the doctor
/// decided, and on what stated grounds.
///
/// The decision is never implicit. Approving issues a fresh prescription with
/// its own document and verification code; declining requires a reason the
/// patient can read and act on. A refusal with no reason is the failure mode
/// this whole model exists to prevent — the patient cannot tell whether to book
/// a review, wait, or stop taking the medicine.
@immutable
class RefillRequest {
  const RefillRequest({
    required this.id,
    required this.prescriptionId,
    required this.doctorName,
    required this.requestedAt,
    required this.status,
    this.patientNote,
    this.decidedAt,
    this.declineReason,
    this.decisionNote,
    this.issuedPrescriptionId,
  });

  final String id;
  final String prescriptionId;

  /// Snapshot, like everywhere else in this feature: the request must read the
  /// same later even if the doctor changes their display name.
  final String doctorName;

  final DateTime requestedAt;
  final RefillStatus status;

  /// The patient's own words. Optional, and capped — it is context for the
  /// doctor, not a consultation.
  final String? patientNote;

  final DateTime? decidedAt;

  /// Set only on a decline, and always set on one.
  final RefillDeclineReason? declineReason;

  /// The doctor's note on the decision. **Required when declining.**
  final String? decisionNote;

  /// The prescription an approval produced.
  final String? issuedPrescriptionId;

  static const maxPatientNoteLength = 300;
  static const maxDecisionNoteLength = 300;

  bool get isOpen => status.isOpen;

  bool get canCancel => status.isOpen;

  /// Whether [prescription] can be asked to be repeated at all.
  ///
  /// Only a live prescription: a cancelled or superseded one has been replaced
  /// or withdrawn by a clinician, and repeating it would quietly reinstate a
  /// decision somebody deliberately made.
  static bool canRequestFor(Prescription prescription) => prescription.isValid;

  factory RefillRequest.fromJson(Map<String, dynamic> json) => RefillRequest(
        id: json['id'] as String,
        prescriptionId: json['prescriptionId'] as String,
        doctorName: json['doctorName'] as String? ?? '',
        requestedAt: DateTime.parse(json['requestedAt'] as String).toLocal(),
        status: RefillStatus.fromWire(json['status'] as String?),
        patientNote: json['patientNote'] as String?,
        decidedAt: json['decidedAt'] == null
            ? null
            : DateTime.parse(json['decidedAt'] as String).toLocal(),
        declineReason: json['declineReason'] == null
            ? null
            : RefillDeclineReason.fromWire(json['declineReason'] as String?),
        decisionNote: json['decisionNote'] as String?,
        issuedPrescriptionId: json['issuedPrescriptionId'] as String?,
      );

  RefillRequest copyWith({
    RefillStatus? status,
    DateTime? decidedAt,
    RefillDeclineReason? declineReason,
    String? decisionNote,
    String? issuedPrescriptionId,
  }) =>
      RefillRequest(
        id: id,
        prescriptionId: prescriptionId,
        doctorName: doctorName,
        requestedAt: requestedAt,
        status: status ?? this.status,
        patientNote: patientNote,
        decidedAt: decidedAt ?? this.decidedAt,
        declineReason: declineReason ?? this.declineReason,
        decisionNote: decisionNote ?? this.decisionNote,
        issuedPrescriptionId: issuedPrescriptionId ?? this.issuedPrescriptionId,
      );
}
