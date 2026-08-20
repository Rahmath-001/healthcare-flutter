import 'package:flutter/foundation.dart';

/// Blood group.
///
/// An enum rather than a free string because it is clinical data that a doctor
/// may act on: "O+" and "0+" are one keystroke apart and only one of them is a
/// blood group.
enum BloodGroup {
  aPositive('A_POSITIVE', 'A+'),
  aNegative('A_NEGATIVE', 'A-'),
  bPositive('B_POSITIVE', 'B+'),
  bNegative('B_NEGATIVE', 'B-'),
  abPositive('AB_POSITIVE', 'AB+'),
  abNegative('AB_NEGATIVE', 'AB-'),
  oPositive('O_POSITIVE', 'O+'),
  oNegative('O_NEGATIVE', 'O-');

  const BloodGroup(this.wire, this.label);

  final String wire;
  final String label;

  static BloodGroup? fromWire(String? wire) {
    if (wire == null) return null;
    for (final v in BloodGroup.values) {
      if (v.wire == wire) return v;
    }
    return null;
  }
}

enum Gender {
  female('FEMALE', 'Female'),
  male('MALE', 'Male'),
  other('OTHER', 'Other'),
  undisclosed('UNDISCLOSED', 'Prefer not to say');

  const Gender(this.wire, this.label);

  final String wire;
  final String label;

  static Gender? fromWire(String? wire) {
    if (wire == null) return null;
    for (final v in Gender.values) {
      if (v.wire == wire) return v;
    }
    return null;
  }
}

/// The patient's own profile.
///
/// Everything below `displayName` is clinical and lives server-side only. An
/// earlier build wrote age and blood group to SharedPreferences, which is
/// unencrypted and swept into device backups; `purgeLegacyHealthData()` removes
/// that on upgrade and this type is where the data lives instead.
@immutable
class PatientProfile {
  const PatientProfile({
    required this.userId,
    this.displayName,
    this.email,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.bloodGroup,
    this.allergies = const [],
    this.chronicConditions = const [],
    this.emergencyContactName,
    this.emergencyContactPhone,
  });

  final String userId;
  final String? displayName;
  final String? email;
  final String? phone;
  final DateTime? dateOfBirth;
  final Gender? gender;
  final BloodGroup? bloodGroup;
  final List<String> allergies;
  final List<String> chronicConditions;
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  /// Age is derived, never stored — a stored age is wrong within a year.
  int? get age {
    final dob = dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years;
  }

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    List<String> list(Object? raw) => raw is List
        ? raw.map((e) => e.toString()).toList(growable: false)
        : const [];

    final dob = json['dateOfBirth'] as String?;

    return PatientProfile(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      dateOfBirth: dob == null ? null : DateTime.parse(dob),
      gender: Gender.fromWire(json['gender'] as String?),
      bloodGroup: BloodGroup.fromWire(json['bloodGroup'] as String?),
      allergies: list(json['allergies']),
      chronicConditions: list(json['chronicConditions']),
      emergencyContactName: json['emergencyContactName'] as String?,
      emergencyContactPhone: json['emergencyContactPhone'] as String?,
    );
  }

  PatientProfile withDraft(PatientProfileDraft d) => PatientProfile(
        userId: userId,
        displayName: d.displayName ?? displayName,
        email: email,
        phone: phone,
        dateOfBirth: d.dateOfBirth ?? dateOfBirth,
        gender: d.gender ?? gender,
        bloodGroup: d.bloodGroup ?? bloodGroup,
        allergies: d.allergies ?? allergies,
        chronicConditions: d.chronicConditions ?? chronicConditions,
        emergencyContactName: d.emergencyContactName ?? emergencyContactName,
        emergencyContactPhone: d.emergencyContactPhone ?? emergencyContactPhone,
      );
}

/// A partial update. Null means "leave alone", which is why this is a separate
/// type rather than a full [PatientProfile] with nullable fields — those two
/// meanings of null are not the same and conflating them silently erases data.
@immutable
class PatientProfileDraft {
  const PatientProfileDraft({
    this.displayName,
    this.dateOfBirth,
    this.gender,
    this.bloodGroup,
    this.allergies,
    this.chronicConditions,
    this.emergencyContactName,
    this.emergencyContactPhone,
  });

  final String? displayName;
  final DateTime? dateOfBirth;
  final Gender? gender;
  final BloodGroup? bloodGroup;
  final List<String>? allergies;
  final List<String>? chronicConditions;
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  Map<String, dynamic> toJson() => {
        if (displayName != null) 'displayName': displayName,
        if (dateOfBirth != null) 'dateOfBirth': _dateOnly(dateOfBirth!),
        if (gender != null) 'gender': gender!.wire,
        if (bloodGroup != null) 'bloodGroup': bloodGroup!.wire,
        if (allergies != null) 'allergies': allergies,
        if (chronicConditions != null) 'chronicConditions': chronicConditions,
        if (emergencyContactName != null)
          'emergencyContactName': emergencyContactName,
        if (emergencyContactPhone != null)
          'emergencyContactPhone': emergencyContactPhone,
      };

  /// A birth date is a calendar day, not an instant. Sending it as an ISO
  /// timestamp makes it shift across timezones and quietly change by a day.
  static String _dateOnly(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
