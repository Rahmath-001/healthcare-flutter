import 'package:meta/meta.dart';

/// The three non-personal organisation requests shown in the public wireframe.
enum OrganisationType { hospital, diagnostics, homeHealth }

extension OrganisationTypeWire on OrganisationType {
  String get wire => switch (this) {
        OrganisationType.hospital => 'HOSPITAL',
        OrganisationType.diagnostics => 'LAB_DIAGNOSTICS',
        OrganisationType.homeHealth => 'HOME_HEALTH_PROVIDER',
      };

  String get label => switch (this) {
        OrganisationType.hospital => 'Hospital',
        OrganisationType.diagnostics => 'Lab / Diagnostics',
        OrganisationType.homeHealth => 'Home Health Provider',
      };

  static OrganisationType fromLabel(String value) => switch (value) {
        'Lab / Diagnostics' => OrganisationType.diagnostics,
        'Home Health Provider' => OrganisationType.homeHealth,
        _ => OrganisationType.hospital,
      };
}

/// Contact details submitted for human review. This is a request, not a user
/// role: accepting it must remain an operator action.
@immutable
class OrganisationRegistrationDraft {
  const OrganisationRegistrationDraft({
    required this.type,
    required this.name,
    required this.registrationNumber,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.postalCode,
    required this.state,
  });

  final OrganisationType type;
  final String name;
  final String registrationNumber;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String postalCode;
  final String state;
}

@immutable
class OrganisationRegistrationReceipt {
  const OrganisationRegistrationReceipt({required this.id});

  final String id;

  factory OrganisationRegistrationReceipt.fromJson(Map<String, dynamic> json) =>
      OrganisationRegistrationReceipt(id: json['id'] as String);
}
