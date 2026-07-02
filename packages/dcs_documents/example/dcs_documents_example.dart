import 'package:dcs_documents/dcs_documents.dart';

void main() {
  final payload = const BoardingPassDocument(
    passengerName: 'DOE/JOHN',
    flightNumber: 'AB123',
    origin: 'IKA',
    destination: 'DXB',
    seat: '12A',
    sequenceNumber: '001',
  ).toPayload();

  print(payload.content);
}
