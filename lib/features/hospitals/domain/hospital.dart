import 'package:meta/meta.dart';

/// A hospital that has passed MiDoctor's organisation review.
///
/// The directory deliberately exposes only the public business address. Contact
/// and registration details remain in the review record and are never sent to
/// patients.
@immutable
class HospitalDirectoryEntry {
  const HospitalDirectoryEntry({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
  });

  final String id;
  final String name;
  final String address;
  final String city;
  final String state;
  final String postalCode;
  final String country;

  String get location => '$city, $state';

  factory HospitalDirectoryEntry.fromJson(Map<String, dynamic> json) =>
      HospitalDirectoryEntry(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        postalCode: json['postalCode'] as String? ?? '',
        country: json['country'] as String? ?? 'India',
      );
}

/// A hospital-admin request which is awaiting, or has received, operations review.
@immutable
class HospitalManagementRequest {
  const HospitalManagementRequest({
    required this.id,
    required this.kind,
    required this.status,
    required this.requestedAt,
    this.providerName,
    this.rejectionReason,
  });

  final String id;
  final String kind;
  final String status;
  final DateTime requestedAt;
  final String? providerName;
  final String? rejectionReason;

  bool get isPending => status == 'PENDING';

  String get title => kind == 'PROFILE_CHANGE'
      ? 'Organisation detail update'
      : 'Provider affiliation';

  factory HospitalManagementRequest.fromJson(Map<String, dynamic> json) =>
      HospitalManagementRequest(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? 'PROFILE_CHANGE',
        status: json['status'] as String? ?? 'PENDING',
        requestedAt: DateTime.parse(json['requestedAt'] as String).toLocal(),
        providerName: json['providerName'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
      );
}
