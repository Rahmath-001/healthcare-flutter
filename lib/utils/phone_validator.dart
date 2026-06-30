/// Cheap, client-side pre-check only. The authoritative carrier/VoIP check
/// happens server-side via the `verifyIndianCarrier` Cloud Function, because
/// India Mobile Number Portability makes prefix->carrier mapping unreliable.
class PhoneValidator {
  /// Indian mobile: 10 digits, leading 6-9.
  static final RegExp _national = RegExp(r'^[6-9]\d{9}$');

  /// Strip spaces, dashes, leading +91/0091/91/0 -> bare 10-digit national.
  static String normalizeNational(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (s.startsWith('+91')) {
      s = s.substring(3);
    } else if (s.startsWith('0091')) {
      s = s.substring(4);
    } else if (s.startsWith('91') && s.length == 12) {
      s = s.substring(2);
    } else if (s.startsWith('0') && s.length == 11) {
      s = s.substring(1);
    }
    return s;
  }

  static bool isValidNational(String raw) =>
      _national.hasMatch(normalizeNational(raw));

  /// E.164 form for Firebase / Twilio, e.g. +919876543210.
  static String toE164(String raw) => '+91${normalizeNational(raw)}';
}
