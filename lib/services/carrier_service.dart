import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Result of the server-side carrier/VoIP check.
class CarrierResult {
  final bool ok;
  final String? carrier;
  final String? type; // mobile | voip | landline | null
  final String? reason;

  const CarrierResult({
    required this.ok,
    this.carrier,
    this.type,
    this.reason,
  });
}

/// Calls the `verifyIndianCarrier` Cloud Function. The function uses Twilio
/// Lookup to confirm the number is a mobile line on Airtel/Jio/Vi and is NOT
/// VoIP. Twilio credentials live only on the server.
///
/// SECURITY: this check is **advisory by construction**. The client calls the
/// function and then separately calls Firebase Auth, so a repackaged APK can
/// simply skip it. Treat it as a UX filter that gives the user a clear message
/// before an OTP is burned — not as an access control.
///
/// Real enforcement moves server-side in Phase 1: the API re-runs Twilio Lookup
/// on the phone number inside the verified Firebase ID token before minting a
/// MiDoctor session, and Firebase App Check (Play Integrity / App Attest)
/// becomes the actual anti-abuse control. This class is deleted at that point.
class CarrierService {
  final FirebaseFunctions _functions;

  /// Firebase Authentication test phone numbers do not correspond to a real
  /// carrier, so Twilio Lookup cannot validate them.  This flag is deliberately
  /// effective only in a debug build: it skips an advisory UX check, never the
  /// Firebase phone-verification flow that proves possession of the number.
  static const _skipCarrierCheckForTestPhone =
      bool.fromEnvironment('SKIP_CARRIER_CHECK');

  CarrierService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  Future<CarrierResult> verify(String e164) async {
    if (kDebugMode && _skipCarrierCheckForTestPhone) {
      return const CarrierResult(
        ok: true,
        reason: 'Carrier check skipped for a Firebase test phone number.',
      );
    }

    try {
      final callable = _functions.httpsCallable('verifyIndianCarrier');
      final res = await callable.call<Map<String, dynamic>>({'phone': e164});
      final data = res.data;
      return CarrierResult(
        ok: data['ok'] == true,
        carrier: data['carrier'] as String?,
        type: data['type'] as String?,
        reason: data['reason'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      // Carrier Lookup is an optional UX / fraud signal, not the authenticator:
      // Firebase Phone Auth is what proves possession of the phone number. A
      // missing Twilio configuration must therefore not turn a valid Firebase
      // SMS verification into a sign-in outage. Once Lookup is configured, its
      // successful `ok: false` response still rejects known VoIP/landline
      // numbers before Firebase sends an SMS.
      if (e.code == 'not-found' ||
          e.code == 'unavailable' ||
          e.code == 'internal' ||
          e.code == 'failed-precondition') {
        return const CarrierResult(
          ok: true,
          reason: 'Carrier not verified (optional check unavailable).',
        );
      }
      return CarrierResult(ok: false, reason: e.message ?? 'Lookup failed');
    } catch (e) {
      // Same rule for a transport failure that is not surfaced as a Functions
      // error: do not make an optional pre-flight a second OTP provider.
      return const CarrierResult(
        ok: true,
        reason: 'Carrier not verified (optional check unavailable).',
      );
    }
  }
}
