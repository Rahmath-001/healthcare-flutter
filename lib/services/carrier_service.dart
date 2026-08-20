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

  CarrierService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  Future<CarrierResult> verify(String e164) async {
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
      // Function not deployed (e.g. Twilio/Blaze not set up yet).
      //
      // In debug this degrades to "unverified" so the app is usable without a
      // deployed backend. In release it fails CLOSED: a healthcare app must not
      // silently drop a fraud control because a dependency is missing, and an
      // undeployed function in production is an outage, not a pass.
      if (e.code == 'not-found') {
        if (kDebugMode) {
          return const CarrierResult(
            ok: true,
            reason: 'Carrier not verified (server check unavailable, debug).',
          );
        }
        return const CarrierResult(
          ok: false,
          reason: 'Verification is temporarily unavailable. Please try again.',
        );
      }
      return CarrierResult(ok: false, reason: e.message ?? 'Lookup failed');
    } catch (e) {
      return CarrierResult(ok: false, reason: 'Lookup failed: $e');
    }
  }
}
