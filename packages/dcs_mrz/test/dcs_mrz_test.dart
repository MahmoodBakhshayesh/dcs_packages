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

    test('computes check digit', () {
      expect(checkDigit('L898902C3'), '6');
    });
  });
}
