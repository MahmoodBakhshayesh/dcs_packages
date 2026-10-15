import 'package:dcs_zebra/dcs_zebra.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dcs_zebra');
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'discover':
          return [
            {
              'id': 'bluetooth:AA:BB:CC:DD:EE:FF',
              'address': 'AA:BB:CC:DD:EE:FF',
              'connectionType': 'bluetooth',
              'name': 'ZQ620',
              'model': 'ZQ620',
              'rssi': -55,
              'paired': false,
              'manufacturer': 'Zebra',
            },
          ];
        case 'startDiscover':
          return null;
        case 'cancelDiscover':
          return null;
        case 'pair':
          return 'paired';
        case 'unpair':
          return 'unpaired';
        case 'bondedPrinters':
          return [
            {
              'id': 'bluetooth:11:22:33:44:55:66',
              'address': '11:22:33:44:55:66',
              'connectionType': 'bluetooth',
              'name': 'ZQ520',
              'model': 'ZQ520',
              'paired': true,
              'manufacturer': 'Zebra',
            },
          ];
        case 'pairedAccessories':
          return [
            {
              'id': 'bluetooth:SN123',
              'address': 'SN123',
              'connectionType': 'bluetooth',
              'name': 'iMZ320',
              'model': 'iMZ320',
              'paired': true,
            },
          ];
        case 'ensureBluetoothPermissions':
          return 'granted';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('discover maps rssi and paired', () async {
    final client = ZebraClient();
    final found = await client.discover(
      types: [ZebraConnectionType.bluetooth],
      zebraOnly: false,
    );
    expect(found, hasLength(1));
    expect(found.first.rssi, -55);
    expect(found.first.paired, isFalse);
    expect(found.first.isMobileModel, isTrue);
    await client.dispose();
  });

  test('pair / unpair / bonded / permissions', () async {
    final client = ZebraClient();
    const descriptor = ZebraPrinterDescriptor(
      id: 'bluetooth:AA:BB:CC:DD:EE:FF',
      address: 'AA:BB:CC:DD:EE:FF',
      connectionType: ZebraConnectionType.bluetooth,
      name: 'ZQ620',
      model: 'ZQ620',
    );

    expect(await client.pair(descriptor), ZebraPairingResult.paired);
    expect(await client.unpair(descriptor), ZebraPairingResult.unpaired);
    final bonded = await client.bondedPrinters();
    expect(bonded.single.paired, isTrue);
    expect(bonded.single.isMobileModel, isTrue);
    final accessories = await client.pairedAccessories();
    expect(accessories.single.model, 'iMZ320');
    expect(await client.ensureBluetoothPermissions(), ZebraPermissionState.granted);

    expect(log.map((c) => c.method), containsAll([
      'pair',
      'unpair',
      'bondedPrinters',
      'pairedAccessories',
      'ensureBluetoothPermissions',
    ]));
    await client.dispose();
  });

  test('iOS openSystemSettings pairing result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pair') return 'openSystemSettings';
      return null;
    });
    final client = ZebraClient();
    final result = await client.pair(
      const ZebraPrinterDescriptor(
        id: 'bluetooth:1',
        address: '1',
        connectionType: ZebraConnectionType.bluetooth,
      ),
    );
    expect(result, ZebraPairingResult.openSystemSettings);
    await client.dispose();
  });
}
