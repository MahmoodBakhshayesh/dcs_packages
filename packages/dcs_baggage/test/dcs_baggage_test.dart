import 'package:dcs_baggage/dcs_baggage.dart';
import 'package:test/test.dart';

void main() {
  group('baggage', () {
    test('validates tag number shape', () {
      expect(const BaggageTag(airlineNumericCode: '123', serialNumber: '456789').isValid, isTrue);
      expect(const BaggageTag(airlineNumericCode: '12', serialNumber: '456789').isValid, isFalse);
    });

    test('marks complete baggage service message', () {
      final message = BaggageServiceMessage(
        type: BaggageMessageType.bsm,
        flightNumber: 'AB123',
        origin: 'IKA',
        bags: const [
          CheckedBag(
            tag: BaggageTag(airlineNumericCode: '123', serialNumber: '456789'),
            destination: 'DXB',
          ),
        ],
      );

      expect(message.isComplete, isTrue);
    });
  });
}
