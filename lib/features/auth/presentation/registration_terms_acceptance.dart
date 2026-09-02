import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/registration_terms_acceptance.dart';

/// Holds an acknowledgement only long enough to include it in the first
/// Firebase-to-MiDoctor session exchange. The durable record is server-side.
class RegistrationTermsAcceptanceNotifier
    extends Notifier<RegistrationTermsAcceptance?> {
  @override
  RegistrationTermsAcceptance? build() => null;

  void acceptCurrentTerms() => state = RegistrationTermsAcceptance.current;

  void clear() => state = null;
}

final registrationTermsAcceptanceProvider = NotifierProvider<
    RegistrationTermsAcceptanceNotifier, RegistrationTermsAcceptance?>(
  RegistrationTermsAcceptanceNotifier.new,
);
