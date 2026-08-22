import 'package:meta/meta.dart';

import 'prescription.dart';

/// One medicine inside a saved template.
///
/// Deliberately not a [PrescriptionItem]. That type is a line on an issued
/// legal document — a snapshot of what was prescribed, which is why it carries
/// no telemedicine classification: a later catalogue edit must not be able to
/// change what a doctor is recorded as having prescribed.
///
/// A template is the opposite. It is a plan, and its classification is
/// **resolved from the catalogue every time the template is read**, never
/// stored. So when the regulator moves a drug to List B, every saved template
/// containing it starts refusing on first consultations that same day, with no
/// migration and nothing to remember.
@immutable
class TemplateItem {
  const TemplateItem({
    required this.drugId,
    required this.drugName,
    required this.genericName,
    required this.strength,
    required this.form,
    required this.frequency,
    required this.durationDays,
    required this.telemedicineList,
    this.instructions,
  });

  /// What the catalogue is re-read by. A template item without one cannot be
  /// re-checked, so it is refused at save time rather than silently kept.
  final String drugId;

  final String drugName;
  final String genericName;
  final String strength;
  final String form;
  final String frequency;
  final int durationDays;
  final String? instructions;

  /// As of the moment this template was read, not the moment it was saved.
  final TelemedicineDrugList telemedicineList;

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

  /// The composer line this becomes once applied.
  PrescriptionItem toPrescriptionItem() => PrescriptionItem(
        drugId: drugId,
        drugName: drugName,
        genericName: genericName,
        strength: strength,
        form: form,
        frequency: frequency,
        durationDays: durationDays,
        instructions: instructions,
      );

  factory TemplateItem.fromJson(Map<String, dynamic> json) => TemplateItem(
        drugId: json['drugId'] as String,
        drugName: json['drugName'] as String,
        genericName: (json['genericName'] as String?) ?? '',
        strength: json['strength'] as String,
        form: (json['form'] as String?) ?? '',
        frequency: json['frequency'] as String,
        durationDays: (json['durationDays'] as num).toInt(),
        instructions: json['instructions'] as String?,
        telemedicineList:
            TelemedicineDrugList.fromWire(json['telemedicineList'] as String?),
      );

  Map<String, dynamic> toJson() => {
        // Only what identifies and doses the drug. Display text and the
        // classification both come back from the catalogue on read, so sending
        // them would be storing a second copy that can go stale.
        'drugId': drugId,
        'strength': strength,
        'frequency': frequency,
        'durationDays': durationDays,
        if (instructions != null) 'instructions': instructions,
      };
}

/// A saved set of medicines a doctor reaches for repeatedly.
///
/// ## Applying one prescribes nothing
///
/// It fills the composer. Every item then goes through the same drug-list
/// check as one typed by hand — greyed out on the client, and re-resolved from
/// the catalogue by the server on issue.
///
/// That is the whole safety story. A template saved during a follow-up may
/// contain a List B medicine, which is refill-only; applied on a first
/// consultation those items are not prescribable. A template that carried its
/// own permission would be a way to launder a drug past a rule the doctor met
/// once, months ago, for a different patient.
@immutable
class PrescriptionTemplate {
  const PrescriptionTemplate({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
    this.diagnosis,
    this.advice,
  });

  final String id;

  /// The doctor's own label — "URI adults", "Post-op day 1".
  final String name;

  final List<TemplateItem> items;
  final DateTime createdAt;

  /// Offered as a starting point, never applied silently.
  ///
  /// A diagnosis is about a patient, not about a set of drugs. A template that
  /// quietly filled in "Acute pharyngitis" for somebody who does not have it
  /// is a clinical error the doctor did not make.
  final String? diagnosis;
  final String? advice;

  static const maxNameLength = 60;
  static const maxItems = 20;

  bool get isEmpty => items.isEmpty;

  /// The items that may be prescribed on this consultation.
  List<TemplateItem> prescribableOn({required bool isFollowUp}) => items
      .where((i) => i.isPrescribableOn(isFollowUp: isFollowUp))
      .toList(growable: false);

  /// The items that may not, so the doctor can be warned before applying
  /// rather than surprised by greyed-out rows afterwards.
  List<TemplateItem> blockedOn({required bool isFollowUp}) => items
      .where((i) => !i.isPrescribableOn(isFollowUp: isFollowUp))
      .toList(growable: false);

  factory PrescriptionTemplate.fromJson(Map<String, dynamic> json) =>
      PrescriptionTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        diagnosis: json['diagnosis'] as String?,
        advice: json['advice'] as String?,
        items: ((json['items'] as List<dynamic>?) ?? const [])
            .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}
