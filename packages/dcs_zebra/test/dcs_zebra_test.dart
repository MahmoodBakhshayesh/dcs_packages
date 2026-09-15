import 'package:dcs_zebra/dcs_zebra.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZebraStatusParser', () {
    const printer = ZebraPrinterDescriptor(
      id: 'tcp:192.168.1.1:9100',
      address: '192.168.1.1:9100',
      connectionType: ZebraConnectionType.tcp,
      role: ZebraPrinterRole.boardingPass,
    );

    test('parses ready host status', () {
      const raw = '030,0,0,1248,000,0,0,0,000,0,0,0\n'
          '000,0,0,0,0,2,6,0,00000000,1,000\n'
          '1234,0';
      final status = ZebraStatusParser.fromHostStatus(raw, printer: printer);
      expect(status.paperOut, isFalse);
      expect(status.paused, isFalse);
      expect(status.readyToPrint, isTrue);
      expect(status.hardwareStatusLabel, 'ready');
    });

    test('parses paper out', () {
      const raw = '030,1,0,1248,000,0,0,0,000,0,0,0\n000,0,0,0,0,2,6,0,00000000,1,000';
      final status = ZebraStatusParser.fromHostStatus(raw, printer: printer);
      expect(status.paperOut, isTrue);
      expect(status.readyToPrint, isFalse);
      expect(status.hardwareStatusLabel, 'paper_out');
    });

    test('parses native status map', () {
      final status = ZebraStatusParser.fromNativeMap(
        {
          'isReadyToPrint': false,
          'isHeadOpen': true,
          'isPaperOut': false,
        },
        printer: printer,
      );
      expect(status.headOpen, isTrue);
      expect(status.hardwareStatusLabel, 'head_open');
    });
  });

  group('ZebraStatusAssets', () {
    test('maps role and visual status to asset path', () {
      expect(
        ZebraStatusAssets.forRole(
          ZebraPrinterRole.bagTag,
          ZebraDeviceVisualStatus.paperOut,
        ),
        'assets/images/icons/bt/bt_paper_out.png',
      );
    });

    test('maps printer status to visual asset', () {
      const printer = ZebraPrinterDescriptor(
        id: 'p1',
        address: '1',
        connectionType: ZebraConnectionType.tcp,
        role: ZebraPrinterRole.boardingPass,
      );
      final status = ZebraPrinterStatus(
        printer: printer,
        state: ZebraPrinterState.ready,
        message: 'ready',
        connected: true,
        readyToPrint: true,
        hardwareStatusLabel: 'ready',
      );
      expect(
        ZebraStatusAssets.forPrinterStatus(status),
        'assets/images/icons/bp/bp_active.png',
      );
    });
  });

  group('ZebraSgd', () {
    test('builds get/set commands', () {
      expect(
        String.fromCharCodes(ZebraSgd.getCommand('device.friendly_name')),
        contains('getvar "device.friendly_name"'),
      );
      expect(
        String.fromCharCodes(ZebraSgd.setCommand('device.languages', 'zpl')),
        contains('setvar "device.languages" "zpl"'),
      );
    });
  });

  group('ZebraLogger', () {
    test('keeps recent events', () async {
      final logger = ZebraLogger();
      logger.call(ZebraLogLevel.info, ZebraLogScope.client, 'hello');
      expect(logger.recent, hasLength(1));
      expect(logger.recent.first.message, 'hello');
      await logger.close();
    });
  });

  group('ZebraPrinterIdentity', () {
    test('accepts zebra printer names', () {
      expect(
        ZebraPrinterIdentity.looksLikeZebraText('Zebra ZQ620'),
        isTrue,
      );
      expect(
        ZebraPrinterIdentity.looksLikeZebra(
          const ZebraPrinterDescriptor(
            id: 'bluetooth:AA:BB',
            address: 'AA:BB',
            connectionType: ZebraConnectionType.bluetooth,
            name: 'ZD421',
          ),
        ),
        isTrue,
      );
    });

    test('rejects non-printer bluetooth devices', () {
      expect(
        ZebraPrinterIdentity.looksLikeZebraText("Mahmood's Buds2"),
        isFalse,
      );
      expect(
        ZebraPrinterIdentity.looksLikeZebraText('Galaxy Buds'),
        isFalse,
      );
    });
  });
}
