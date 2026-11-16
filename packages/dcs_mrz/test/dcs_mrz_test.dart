import 'package:dcs_mrz/dcs_mrz.dart';
import 'package:test/test.dart';

void main() {
  group('MRZ TD3 parser', () {
    test('parses and validates sample passport MRZ', () {
      final document = MrzTd3Document.parse(
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
        'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
      );

      expect(document.primaryIdentifier, 'ERIKSSON');
      expect(document.secondaryIdentifier, 'ANNA MARIA');
      expect(document.valid, isTrue);
    });

    test('accepts filler as the check digit of an empty optional data field', () {
      // Optional data all '<' → its check digit may be '<' (ICAO 9303-4); other digits unchanged.
      const line2 = 'L898902C36UTO7408122F1204159<<<<<<<<<<<<<<<0';
      final withZero = MrzTd3Document.parse('P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<', line2);
      expect(withZero.valid, isTrue);
      final withFiller = MrzTd3Document.parse(
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
        '${line2.substring(0, 42)}<${line2.substring(43)}',
      );
      expect(withFiller.valid, isTrue);
    });

    test('filler check digit is rejected when optional data is present', () {
      final document = MrzTd3Document.parse(
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
        'L898902C36UTO7408122F1204159ZE184226B<<<<<<0',
      );
      expect(document.valid, isFalse);
    });

    test('computes check digit', () {
      expect(checkDigit('L898902C3'), '6');
    });
  });
}
