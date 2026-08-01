import 'package:dcs_cute_peripherals/dcs_cute_peripherals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArincRqb', () {
    test('encode/decode roundtrip', () {
      final original = ArincRqb.send([0x61, 0x2f, ...'QS'.codeUnits]);
      original.commandStatus = 0;
      original.physicalStatus = 3;
      final encoded = original.encode();
      expect(encoded.length, 16 + original.body.length);

      final decoded = ArincRqb.decode(encoded);
      expect(decoded.command, ArincPcpCommand.send);
      expect(decoded.body, original.body);
      expect(decoded.dataLength, original.body.length);
    });

    test('header-only command packet', () {
      final packet = ArincRqb.commandOnly(
        ArincPcpCommand.mode,
        parameters: [ArincPcpMode.unsolicitedReadWrite, 0, 0, 0],
      );
      final bytes = packet.encode();
      expect(bytes.length, 16);
      final decoded = ArincRqb.decode(bytes);
      expect(decoded.command, ArincPcpCommand.mode);
      expect(decoded.parameters[0], ArincPcpMode.unsolicitedReadWrite);
    });
  });

  group('AeaHelpers', () {
    test('ARINC wrap', () {
      final wrapped = AeaHelpers.wrapArincAea('QS'.codeUnits);
      expect(wrapped[0], 0x61);
      expect(wrapped[1], 0x2f);
      expect(String.fromCharCodes(wrapped.sublist(2)), 'QS');
    });

    test('SITA frame', () {
      final framed = AeaHelpers.frameSita('PT01'.codeUnits, addAdPrefix: true);
      expect(framed.first, 0x80);
      expect(framed.last, 0xff);
      expect(String.fromCharCodes(framed.sublist(1, framed.length - 1)).startsWith('AD;'), isTrue);
    });
  });
}
