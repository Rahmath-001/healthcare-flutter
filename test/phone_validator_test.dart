import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/utils/phone_validator.dart';

void main() {
  group('normalizeNational', () {
    test('bare 10 digits pass through', () {
      expect(PhoneValidator.normalizeNational('9876543210'), '9876543210');
    });
    test('strips +91 prefix', () {
      expect(PhoneValidator.normalizeNational('+919876543210'), '9876543210');
    });
    test('strips 0091 prefix', () {
      expect(PhoneValidator.normalizeNational('00919876543210'), '9876543210');
    });
    test('strips 91 when 12 digits', () {
      expect(PhoneValidator.normalizeNational('919876543210'), '9876543210');
    });
    test('strips leading 0 trunk prefix', () {
      expect(PhoneValidator.normalizeNational('09876543210'), '9876543210');
    });
    test('strips spaces and dashes', () {
      expect(PhoneValidator.normalizeNational('+91 98765-43210'), '9876543210');
    });
  });

  group('isValidNational', () {
    test('valid 10-digit starting 6-9', () {
      expect(PhoneValidator.isValidNational('6000000000'), true);
      expect(PhoneValidator.isValidNational('7123456789'), true);
      expect(PhoneValidator.isValidNational('8999999999'), true);
      expect(PhoneValidator.isValidNational('9876543210'), true);
    });
    test('rejects starting with 0-5', () {
      expect(PhoneValidator.isValidNational('0123456789'), false);
      expect(PhoneValidator.isValidNational('1234567890'), false);
      expect(PhoneValidator.isValidNational('5000000000'), false);
    });
    test('rejects wrong length', () {
      expect(PhoneValidator.isValidNational('98765'), false);
      expect(PhoneValidator.isValidNational('98765432101'), false);
      expect(PhoneValidator.isValidNational(''), false);
    });
    test('works with prefixed input', () {
      expect(PhoneValidator.isValidNational('+919876543210'), true);
      expect(PhoneValidator.isValidNational('09876543210'), true);
    });
  });

  group('toE164', () {
    test('bare digits', () {
      expect(PhoneValidator.toE164('9876543210'), '+919876543210');
    });
    test('already prefixed', () {
      expect(PhoneValidator.toE164('+919876543210'), '+919876543210');
    });
    test('with spaces', () {
      expect(PhoneValidator.toE164('98765 43210'), '+919876543210');
    });
  });
}
