import 'package:flutter/foundation.dart';

/// A hospital or clinic a doctor practises at.
///
/// Modelled as a first-class entity: the spec allows search-by-hospital and
/// requires a hospital affiliation letter, yet never defines a hospital, so
/// there was nothing for either to point at.
@immutable
class Hospital {
  const Hospital({
    required this.id,
    required this.name,
    required this.city,
    this.address,
  });

  final String id;
  final String name;
  final String city;
  final String? address;

  factory Hospital.fromJson(Map<String, dynamic> json) => Hospital(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        city: json['city'] as String? ?? '',
        address: json['address'] as String?,
      );
}

@immutable
class Specialty {
  const Specialty({required this.code, required this.name});
  final String code;
  final String name;

  factory Specialty.fromJson(Map<String, dynamic> json) => Specialty(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

/// Modes a consultation can take. FR-TEL-001 requires all three.
enum ConsultationMode {
  inPerson,
  video,
  audio;

  /// Wire values are UPPER_SNAKE, matching the API's enums.
  String get wire => switch (this) {
        ConsultationMode.inPerson => 'IN_PERSON',
        ConsultationMode.video => 'VIDEO',
        ConsultationMode.audio => 'AUDIO',
      };

  static ConsultationMode fromWire(String? raw) => switch (raw?.toUpperCase()) {
        'IN_PERSON' => ConsultationMode.inPerson,
        'AUDIO' => ConsultationMode.audio,
        _ => ConsultationMode.video,
      };

  String get label => switch (this) {
        ConsultationMode.inPerson => 'In person',
        ConsultationMode.video => 'Video',
        ConsultationMode.audio => 'Audio',
      };
}

/// A verified, approved provider as a patient sees them.
///
/// Only approved providers are ever returned by search — an unverified one has
/// no `doctor:search` visibility at all.
@immutable
class Doctor {
  const Doctor({
    required this.id,
    required this.name,
    required this.specialties,
    required this.qualification,
    required this.registrationNumber,
    required this.yearsExperience,
    required this.consultationFeeInr,
    required this.videoFeeInr,
    required this.rating,
    required this.ratingCount,
    required this.hospital,
    required this.languages,
    required this.modes,
    this.photoUrl,
    this.bio,
  });

  final String id;
  final String name;
  final List<Specialty> specialties;
  final String qualification;

  /// NMC / State Medical Council registration number.
  ///
  /// Displayed wherever the doctor is shown, because the MoHFW Telemedicine
  /// Practice Guidelines require the registration number to be visible to the
  /// patient before and during a consultation.
  final String registrationNumber;

  final int yearsExperience;
  final int consultationFeeInr;
  final int videoFeeInr;
  final double rating;
  final int ratingCount;
  final Hospital hospital;
  final List<String> languages;
  final List<ConsultationMode> modes;
  final String? photoUrl;
  final String? bio;

  String get specialtyLabel => specialties.map((s) => s.name).join(', ');

  int feeFor(ConsultationMode mode) =>
      mode == ConsultationMode.inPerson ? consultationFeeInr : videoFeeInr;

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        specialties: (json['specialties'] as List<dynamic>? ?? const [])
            .map((s) => Specialty.fromJson(s as Map<String, dynamic>))
            .toList(),
        qualification: json['qualification'] as String? ?? '',
        registrationNumber: json['registrationNumber'] as String? ?? '',
        yearsExperience: (json['yearsExperience'] as num?)?.toInt() ?? 0,
        consultationFeeInr: (json['consultationFeeInr'] as num?)?.toInt() ?? 0,
        videoFeeInr: (json['videoFeeInr'] as num?)?.toInt() ?? 0,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
        hospital: Hospital.fromJson(
            json['hospital'] as Map<String, dynamic>? ?? const {}),
        languages: (json['languages'] as List<dynamic>? ?? const [])
            .map((l) => l.toString())
            .toList(),
        modes: (json['modes'] as List<dynamic>? ?? const [])
            .map((m) => ConsultationMode.fromWire(m as String?))
            .toList(),
        photoUrl: json['photoUrl'] as String?,
        bio: json['bio'] as String?,
      );
}

/// Search filters. Mirrors FR-SRCH-001/002 plus the mode filter that
/// telemedicine implies but the spec never lists.
@immutable
class DoctorSearchFilters {
  const DoctorSearchFilters({
    this.query = '',
    this.specialtyCode,
    this.city,
    this.maxFeeInr,
    this.minRating,
    this.mode,
    this.availableToday = false,
  });

  final String query;
  final String? specialtyCode;
  final String? city;
  final int? maxFeeInr;
  final double? minRating;
  final ConsultationMode? mode;
  final bool availableToday;

  bool get isEmpty =>
      query.isEmpty &&
      specialtyCode == null &&
      city == null &&
      maxFeeInr == null &&
      minRating == null &&
      mode == null &&
      !availableToday;

  /// Number of active filters, for the "Filters (2)" badge.
  int get activeCount => [
        specialtyCode,
        city,
        maxFeeInr,
        minRating,
        mode,
        availableToday ? true : null,
      ].whereType<Object>().length;

  DoctorSearchFilters copyWith({
    String? query,
    Object? specialtyCode = _unset,
    Object? city = _unset,
    Object? maxFeeInr = _unset,
    Object? minRating = _unset,
    Object? mode = _unset,
    bool? availableToday,
  }) {
    return DoctorSearchFilters(
      query: query ?? this.query,
      specialtyCode: specialtyCode == _unset
          ? this.specialtyCode
          : specialtyCode as String?,
      city: city == _unset ? this.city : city as String?,
      maxFeeInr: maxFeeInr == _unset ? this.maxFeeInr : maxFeeInr as int?,
      minRating: minRating == _unset ? this.minRating : minRating as double?,
      mode: mode == _unset ? this.mode : mode as ConsultationMode?,
      availableToday: availableToday ?? this.availableToday,
    );
  }

  static const _unset = Object();
}
