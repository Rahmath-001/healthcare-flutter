import 'package:cloud_functions/cloud_functions.dart';

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
      // Cloud Function not deployed yet (e.g. Twilio/Blaze not set up):
      // degrade to "unverified" rather than blocking sign-in entirely.
      if (e.code == 'not-found') {
        return const CarrierResult(
          ok: true,
          reason: 'Carrier not verified (server check unavailable).',
        );
      }
      return CarrierResult(ok: false, reason: e.message ?? 'Lookup failed');
    } catch (e) {
      return CarrierResult(ok: false, reason: 'Lookup failed: $e');
    }
  }
}
