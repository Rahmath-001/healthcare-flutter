import 'package:meta/meta.dart';

/// The legal-copy revisions accepted before a person creates an account.
///
/// The server supplies the timestamp and retention boundary. The client sends
/// only revisions, because a device clock is not evidence of when consent was
/// given.
@immutable
class RegistrationTermsAcceptance {
  const RegistrationTermsAcceptance({
    required this.privacyPolicyVersion,
    required this.termsOfServiceVersion,
  });

  static const current = RegistrationTermsAcceptance(
    privacyPolicyVersion: '2026-09-02',
    termsOfServiceVersion: '2026-09-02',
  );

  final String privacyPolicyVersion;
  final String termsOfServiceVersion;
}
