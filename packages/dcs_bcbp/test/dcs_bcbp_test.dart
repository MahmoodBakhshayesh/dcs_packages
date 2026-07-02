import 'package:dcs_bcbp/dcs_bcbp.dart';
import 'package:test/test.dart';

void main() {
  group('BCBP parser', () {
    test('parses common mandatory fields', () {
      final data = BcbpData.parse(
        'M1DOE/JOHN            EABC1234IKADXB123Y012A0001'.padRight(60),
      );

      expect(data.numberOfLegs, 1);
      expect(data.passengerName.surname, 'DOE');
      expect(data.legs.single.origin, 'IKA');
      expect(data.legs.single.destination, 'DXB');
    });

    test('rejects short payloads', () {
      expect(() => BcbpData.parse('M1SHORT'), throwsA(isA<BcbpParseException>()));
    });
  });
}
