import '../../../core/network/api_client.dart';
import '../domain/organisation_registration.dart';

abstract class OrganisationRegistrationRepository {
  Future<OrganisationRegistrationReceipt> submit(
    OrganisationRegistrationDraft draft,
  );
}

class ApiOrganisationRegistrationRepository
    implements OrganisationRegistrationRepository {
  ApiOrganisationRegistrationRepository(this._api);

  final ApiClient _api;

  @override
  Future<OrganisationRegistrationReceipt> submit(
    OrganisationRegistrationDraft draft,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/organisation-registrations',
      // A prospect is not yet an account. This deliberately has no bearer
      // token requirement; server-side rate limiting protects the public form.
      skipAuth: true,
      body: {
        'type': draft.type.wire,
        'name': draft.name.trim(),
        'registrationNumber': draft.registrationNumber.trim(),
        'email': draft.email.trim(),
        'phone': draft.phone.trim(),
        'address': draft.address.trim(),
        'city': draft.city.trim(),
        'postalCode': draft.postalCode.trim(),
        'state': draft.state.trim(),
        'country': 'India',
      },
    );
    return OrganisationRegistrationReceipt.fromJson(json);
  }
}

/// The form remains usable in explicit fixture mode, but the receipt makes no
/// claim that a real organisation has been registered.
class FixtureOrganisationRegistrationRepository
    implements OrganisationRegistrationRepository {
  @override
  Future<OrganisationRegistrationReceipt> submit(
    OrganisationRegistrationDraft draft,
  ) async =>
      const OrganisationRegistrationReceipt(id: 'fixture-organisation');
}
