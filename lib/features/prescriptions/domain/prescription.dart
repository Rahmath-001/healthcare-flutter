import 'package:flutter/foundation.dart';

/// Telemedicine drug lists from the MoHFW Telemedicine Practice Guidelines 2020.
///
/// The spec says only "provider may create prescriptions", which as written
/// would let a doctor prescribe anything over video. These lists are a legal
/// constraint, not a product preference.
enum TelemedicineDrugList {
  /// Over-the-counter; safe on any consultation type.
  listO('LIST_O'),

  /// Permitted on a first video consultation.
  listA('LIST_A'),

  /// Permitted only as a refill on an established follow-up.
  listB('LIST_B'),

  /// Never prescribable remotely (Schedule X, narcotics, psychotropics).
  prohibited('PROHIBITED');

  const TelemedicineDrugList(this.wire);

  final String wire;

  /// An unrecognised classification is treated as prohibited. Defaulting the
  /// other way would let an unknown drug through on a permissive guess.
  static TelemedicineDrugList fromWire(String? wire) =>
      TelemedicineDrugList.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => TelemedicineDrugList.prohibited,
      );

  String get label => switch (this) {
        TelemedicineDrugList.listO => 'OTC',
        TelemedicineDrugList.listA => 'List A',
        TelemedicineDrugList.listB => 'List B — follow-up only',
        TelemedicineDrugList.prohibited => 'Not allowed remotely',
      };
}

@immutable
class Drug {
  const Drug({
    required this.id,
    required this.name,
    required this.genericName,
    required this.form,
    required this.telemedicineList,
    this.commonStrengths = const [],
  });

  final String id;
  final String name;
  final String genericName;
  final String form;
  final TelemedicineDrugList telemedicineList;
  final List<String> commonStrengths;

  factory Drug.fromJson(Map<String, dynamic> json) => Drug(
        id: json['id'] as String,
        name: json['name'] as String,
        genericName: json['genericName'] as String,
        form: json['form'] as String,
        telemedicineList:
            TelemedicineDrugList.fromWire(json['telemedicineList'] as String?),
        commonStrengths:
            ((json['commonStrengths'] as List<dynamic>?) ?? const [])
                .map((e) => e.toString())
                .toList(growable: false),
      );

  /// Whether this drug may be prescribed on this consultation.
  ///
  /// Mirrors the server-side rule. The client check exists to stop a doctor
  /// composing something that will be rejected, not to enforce the rule —
  /// enforcement is the API's job.
  bool isPrescribableOn({required bool isFollowUp}) =>
      switch (telemedicineList) {
        TelemedicineDrugList.prohibited => false,
        TelemedicineDrugList.listB => isFollowUp,
        _ => true,
      };

  String? blockedReason({required bool isFollowUp}) {
    if (telemedicineList == TelemedicineDrugList.prohibited) {
      return 'This medicine cannot be prescribed in a telemedicine '
          'consultation.';
    }
    if (telemedicineList == TelemedicineDrugList.listB && !isFollowUp) {
      return 'List B medicines can only be prescribed as a refill on a '
          'follow-up consultation.';
    }
    return null;
  }
}

@immutable
class PrescriptionItem {
  const PrescriptionItem({
    this.drugId,
    required this.drugName,
    required this.genericName,
    required this.strength,
    required this.form,
    required this.frequency,
    required this.durationDays,
    this.instructions,
  });

  /// Which catalogue entry this came from.
  ///
  /// Null on an item read back from an issued prescription: that document is a
  /// snapshot of what was prescribed, and the drug's classification at the time
  /// is not something a later catalogue edit should be able to change. Present
  /// when composing, because the server re-resolves the drug by id to decide
  /// whether it may be prescribed at all.
  final String? drugId;

  final String drugName;
  final String genericName;
  final String strength;
  final String form;

  /// Free-text dosing, e.g. "1-0-1" or "Twice daily".
  final String frequency;
  final int durationDays;
  final String? instructions;

  factory PrescriptionItem.fromJson(Map<String, dynamic> json) =>
      PrescriptionItem(
        drugName: json['drugName'] as String,
        genericName: json['genericName'] as String,
        strength: json['strength'] as String,
        form: json['form'] as String,
        frequency: json['frequency'] as String,
        durationDays: (json['durationDays'] as num).toInt(),
        instructions: json['instructions'] as String?,
      );

  String get summary {
    final days = durationDays == 1 ? 'day' : 'days';
    return '$drugName $strength - $frequency - $durationDays $days';
  }
}

enum PrescriptionStatus {
  draft('DRAFT'),
  issued('ISSUED'),
  cancelled('CANCELLED'),
  superseded('SUPERSEDED');

  const PrescriptionStatus(this.wire);

  final String wire;

  static PrescriptionStatus fromWire(String? wire) =>
      PrescriptionStatus.values.firstWhere(
        (v) => v.wire == wire,
        orElse: () => PrescriptionStatus.draft,
      );
}

/// An issued prescription.
///
/// The provider fields are *snapshots* taken at issue time, not references. A
/// prescription is a legal document: it must render exactly as issued even if
/// the doctor later edits their profile, and the NMC registration number must
/// appear on it.
@immutable
class Prescription {
  const Prescription({
    required this.id,
    required this.verificationCode,
    required this.providerName,
    required this.providerQualification,
    required this.providerRegistrationNumber,
    required this.patientName,
    required this.patientAge,
    required this.patientGender,
    required this.issuedAt,
    required this.items,
    required this.status,
    this.diagnosis,
    this.advice,
    this.followUpDate,
    this.appointmentReference,
  });

  final String id;

  /// Printed as a QR code so a pharmacy can confirm the prescription is real
  /// and unaltered.
  final String verificationCode;

  final String providerName;
  final String providerQualification;
  final String providerRegistrationNumber;
  final String patientName;
  final String patientAge;
  final String patientGender;
  final DateTime issuedAt;
  final List<PrescriptionItem> items;
  final PrescriptionStatus status;
  final String? diagnosis;
  final String? advice;
  final DateTime? followUpDate;
  final String? appointmentReference;

  factory Prescription.fromJson(Map<String, dynamic> json) => Prescription(
        id: json['id'] as String,
        verificationCode: json['verificationCode'] as String,
        providerName: json['providerName'] as String,
        providerQualification: json['providerQualification'] as String,
        providerRegistrationNumber:
            json['providerRegistrationNumber'] as String,
        patientName: json['patientName'] as String,
        patientAge: json['patientAge'] as String,
        patientGender: json['patientGender'] as String,
        issuedAt: DateTime.parse(json['issuedAt'] as String).toLocal(),
        status: PrescriptionStatus.fromWire(json['status'] as String?),
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .map((e) => PrescriptionItem.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        diagnosis: json['diagnosis'] as String?,
        advice: json['advice'] as String?,
        followUpDate: json['followUpDate'] == null
            ? null
            : DateTime.parse(json['followUpDate'] as String),
        appointmentReference: json['appointmentReference'] as String?,
      );

  /// Clinical records are retained for three years under NMC guidance.
  DateTime get retainedUntil =>
      DateTime(issuedAt.year + 3, issuedAt.month, issuedAt.day);

  bool get isValid => status == PrescriptionStatus.issued;
}
