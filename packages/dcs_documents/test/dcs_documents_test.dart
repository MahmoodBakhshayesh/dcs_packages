import 'package:dcs_documents/dcs_documents.dart';
import 'package:test/test.dart';

void main() {
  group('documents', () {
    test('boarding pass payload is printable', () {
      final payload = const BoardingPassDocument(
        passengerName: 'DOE/JOHN',
        flightNumber: 'AB123',
        origin: 'IKA',
        destination: 'DXB',
        seat: '12A',
        sequenceNumber: '001',
      ).toPayload();

      expect(payload.isPrintable, isTrue);
      expect(payload.content, contains('AB123 IKA-DXB'));
    });

    test('bag tag uses tag as document id', () {
      final payload = const BagTagDocument(
        tagNumber: '123456789',
        passengerName: 'DOE/JOHN',
        destination: 'DXB',
      ).toPayload();

      expect(payload.documentId, '123456789');
      expect(payload.stockName, 'BTP');
    });
  });
}
