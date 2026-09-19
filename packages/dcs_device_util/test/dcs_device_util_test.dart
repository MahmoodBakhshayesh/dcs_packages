import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dcs_device_util/dcs_device_util.dart';

void main() {
  testWidgets('controller status list renders configured devices', (tester) async {
    final controller = _controllerWithProfiles();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DcsDeviceControllerStatusList(controller: controller),
        ),
      ),
    );

    // Catalog roles render first; scroll to custom profiles below the fold.
    expect(find.text('Boarding Pass Printer'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Boarding Reader'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Boarding Reader'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Bag Printer'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bag Printer'), findsOneWidget);

    await controller.dispose();
  });

  test('cuppsDefaults seeds all CUPPS roles', () {
    final config = DcsDeviceConfig.cuppsDefaults();
    expect(config.profiles.length, DcsDeviceRole.values.length);
    expect(config.profiles.every((p) => !p.enabled), isTrue);
    expect(config.profiles.map((p) => p.id).toSet(), {
      for (final r in DcsDeviceRole.values) r.code,
    });
  });

  test('config round-trip preserves serial and printer options', () {
    final profile = DcsDeviceProfile(
      id: 'bp',
      label: 'Boarding Pass Printer',
      role: DcsDeviceRole.boardingPassPrinter,
      enabled: true,
      matcher: const DcsDeviceMatcher(portName: 'COM30'),
      serialOptions: const DcsSerialOptions(
        baudRate: 115200,
        dtrEnable: true,
        rtsEnable: true,
        receivedBytesThreshold: 1,
        protocolMode: DcsProtocolMode.auto,
      ),
      printerOptions: const DcsPrinterOptions(
        printType: DcsPrintType.aea,
        autoBin: false,
        logoBinary: true,
      ),
    );
    final encoded = DcsDeviceConfig(profiles: [profile]).encode();
    final decoded = DcsDeviceConfig.decode(encoded);
    final bp = decoded.profiles.firstWhere((p) => p.id == 'bp');
    expect(bp.role, DcsDeviceRole.boardingPassPrinter);
    expect(bp.serialOptions.baudRate, 115200);
    expect(bp.serialOptions.dtrEnable, isTrue);
    expect(bp.printerOptions.logoBinary, isTrue);
    expect(bp.comPort, 'COM30');
    // Catalog ensure keeps other CUPPS roles.
    expect(decoded.profiles.length, greaterThanOrEqualTo(DcsDeviceRole.values.length));
  });

  testWidgets('controller status grid renders device cards', (tester) async {
    final controller = _controllerWithProfiles();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DcsDeviceStatusGrid(controller: controller, crossAxisCount: 2),
        ),
      ),
    );

    expect(find.byType(DcsDeviceStatusCard), findsWidgets);
    expect(find.text('Boarding Reader'), findsOneWidget);
    expect(find.text('Bag Printer'), findsOneWidget);

    await controller.dispose();
  });

  test('resolves bundled status asset paths', () {
    expect(
      DcsDeviceStatusAssets.pathFor(
        kind: DcsDeviceKind.printer,
        state: DcsDeviceConnectionState.connected,
      ),
      'assets/devices/dcs_printer_ready.png',
    );
  });

  test('discovers and connects a matching reader profile', () async {
    final adapter = _FakeAdapter(
      devices: const [
        DcsDiscoveredDevice(
          id: 'serial:COM7',
          portName: 'COM7',
          transport: DcsDeviceTransport.serial,
          productName: 'Gate Reader',
        ),
      ],
    );

    final controller = DcsDeviceController(
      initialConfig: DcsDeviceConfig(
        profiles: [
          DcsDeviceProfile(
            id: 'bc',
            label: 'Barcode Reader',
            role: DcsDeviceRole.barcodeReader,
            enabled: true,
            matcher: const DcsDeviceMatcher(portName: 'COM7'),
          ),
        ],
      ),
      adapters: [adapter],
      healthPolicy: const DcsConnectionHealthPolicy(
        heartbeatInterval: Duration(minutes: 1),
      ),
    );

    await controller.start();

    expect(adapter.connectCalls, greaterThanOrEqualTo(1));
    expect(
      controller.currentStatuses['bc']?.state,
      DcsDeviceConnectionState.connected,
    );

    await controller.dispose();
  });

  test('sends queued text request and classifies ok response', () async {
    final adapter = _FakeAdapter(
      devices: const [
        DcsDiscoveredDevice(
          id: 'serial:COM10',
          portName: 'COM10',
          transport: DcsDeviceTransport.serial,
        ),
      ],
      onWrite: (_, data) {
        data.add('HDCAVOK'.codeUnits);
      },
    );

    final controller = DcsDeviceController(
      initialConfig: DcsDeviceConfig(
        profiles: [
          DcsDeviceProfile(
            id: 'bp',
            label: 'BP',
            role: DcsDeviceRole.boardingPassPrinter,
            enabled: true,
            matcher: const DcsDeviceMatcher(portName: 'COM10'),
          ),
        ],
      ),
      adapters: [adapter],
      healthPolicy: const DcsConnectionHealthPolicy(
        heartbeatInterval: Duration(minutes: 1),
      ),
    );

    await controller.start();
    final response = await controller.sendTextRequest(
      'bp',
      'AV',
      options: const DcsDeviceRequestOptions(
        quietWindow: Duration(milliseconds: 1),
      ),
    );

    expect(response.status, DcsDeviceResponseStatus.ok);
    expect(response.text, 'HDCAVOK');

    await controller.dispose();
  });

  test('parses STX ETX framed responses with DLE escaping', () async {
    final session = _FakeSession(
      onWrite: (_, data) {
        data.add([0x02, 0x48, 0x10, 0x03, 0x4F, 0x4B, 0x03]);
      },
    );
    final queue = DcsDeviceRequestQueue(session);

    final response = await queue.sendText(
      'AV',
      options: const DcsDeviceRequestOptions(framed: true),
    );

    expect(response.bytes, [0x48, 0x03, 0x4F, 0x4B]);
    expect(response.status, DcsDeviceResponseStatus.ok);

    await session.close();
  });

  test('auto mode wraps outbound STX/ETX and accepts unframed reply', () async {
    List<int>? written;
    final session = _FakeSession(
      onWrite: (bytes, data) {
        written = List<int>.from(bytes);
        data.add('HDCAVOK'.codeUnits);
      },
    );
    final queue = DcsDeviceRequestQueue(session);

    final response = await queue.sendText(
      'AV',
      options: const DcsDeviceRequestOptions(
        protocolMode: DcsProtocolMode.auto,
        quietWindow: Duration(milliseconds: 1),
      ),
    );

    expect(written, [0x02, 0x41, 0x56, 0x03]);
    expect(response.status, DcsDeviceResponseStatus.ok);
    expect(response.text, 'HDCAVOK');

    await session.close();
  });

  test('framed mode wraps outbound STX/ETX', () async {
    List<int>? written;
    final session = _FakeSession(
      onWrite: (bytes, data) {
        written = List<int>.from(bytes);
        data.add([0x02, ...'HDCAVOK'.codeUnits, 0x03]);
      },
    );
    final queue = DcsDeviceRequestQueue(session);

    final response = await queue.sendText(
      'AV',
      options: const DcsDeviceRequestOptions(
        protocolMode: DcsProtocolMode.framed,
      ),
    );

    expect(written, [0x02, 0x41, 0x56, 0x03]);
    expect(response.status, DcsDeviceResponseStatus.ok);
    expect(response.text, 'HDCAVOK');

    await session.close();
  });

  test('none mode leaves outbound unframed', () {
    expect(
      DcsAeaFraming.encodeOutbound('CP#test'.codeUnits, DcsProtocolMode.none),
      'CP#test'.codeUnits,
    );
    expect(
      DcsAeaFraming.encodeOutbound('CP#test'.codeUnits, DcsProtocolMode.auto)
          .first,
      0x02,
    );
    expect(
      DcsAeaFraming.encodeOutbound('CP#test'.codeUnits, DcsProtocolMode.auto)
          .last,
      0x03,
    );
  });

  test('auto mode prefers STX/ETX framed reply when present', () async {
    final session = _FakeSession(
      onWrite: (_, data) {
        data.add([0x02, ...'HDCPTOK'.codeUnits, 0x03]);
      },
    );
    final queue = DcsDeviceRequestQueue(session);

    final response = await queue.sendText(
      'CP#test',
      options: const DcsDeviceRequestOptions(
        protocolMode: DcsProtocolMode.auto,
        quietWindow: Duration(milliseconds: 50),
      ),
    );

    expect(response.text, 'HDCPTOK');
    expect(response.status, DcsDeviceResponseStatus.ok);

    await session.close();
  });

  test('classifies PTOK print ack as ok', () {
    final status = DcsDeviceRequestOptions.defaultClassifier(
      Uint8List.fromList('HDCPTOK'.codeUnits),
      'HDCPTOK',
    );
    expect(status, DcsDeviceResponseStatus.ok);
  });

  test('classifies EPOK with ERR3IGN param as ok not error', () {
    const text =
        'HDCEPOK#AIRLINEID=119#ERR3IGN=N#UNSOL=Y#STATUSOK=X';
    final status = DcsDeviceRequestOptions.defaultClassifier(
      Uint8List.fromList(text.codeUnits),
      text,
    );
    expect(status, DcsDeviceResponseStatus.ok);
  });

  test('classifies HDCERR7 as error', () {
    const text = 'HDCERR7LC';
    final status = DcsDeviceRequestOptions.defaultClassifier(
      Uint8List.fromList(text.codeUnits),
      text,
    );
    expect(status, DcsDeviceResponseStatus.error);
  });

  test('classifies TRUNCATE=PROK EPOK as ok', () {
    const text = 'HDCEPOK#TRUNCATE=PROK#ERR3IGN=N#ERR5PRT=Y';
    final status = DcsDeviceRequestOptions.defaultClassifier(
      Uint8List.fromList(text.codeUnits),
      text,
    );
    expect(status, DcsDeviceResponseStatus.ok);
  });

  test('isBusyError detects ERR7 only', () {
    expect(DcsDeviceRequestOptions.isBusyError('HDCERR7LC'), isTrue);
    expect(DcsDeviceRequestOptions.isBusyError('HDCEPOK#ERR3IGN=N'), isFalse);
    expect(DcsDeviceRequestOptions.isBusyError('HDCERR6'), isFalse);
  });

  test('fire-and-forget write still frames outbound', () async {
    List<int>? written;
    final session = _FakeSession(
      onWrite: (bytes, data) {
        written = List<int>.from(bytes);
      },
    );
    final queue = DcsDeviceRequestQueue(session);

    final response = await queue.sendText(
      'CP#test',
      options: const DcsDeviceRequestOptions(
        protocolMode: DcsProtocolMode.auto,
        waitForResponse: false,
      ),
    );

    expect(written!.first, 0x02);
    expect(written!.last, 0x03);
    expect(response.status, DcsDeviceResponseStatus.ok);
    expect(response.timedOut, isFalse);

    await session.close();
  });

  test('OCR aliases parse to passport OCR role', () {
    expect(DcsDeviceRole.tryParse('ocr'), DcsDeviceRole.opticalCardReader);
    expect(DcsDeviceRole.opticalCardReader.isPassportReader, isTrue);
    expect(DcsDeviceRole.passportReader.isPassportReader, isTrue);
    expect(DcsDeviceRole.opticalCardReader.label, contains('OCR'));
  });

  test('normalizes LPT and LTP port names', () {
    expect(DcsLptPortAdapter.normalizeLptName('ltp1'), 'LPT1');
    expect(DcsLptPortAdapter.normalizeLptName(r'\\.\LPT2'), 'LPT2');
    expect(DcsLptPortAdapter.normalizeLptName('COM1'), isNull);
  });

  test('COM4 matcher does not bind COM44', () {
    const matcher = DcsDeviceMatcher(portName: 'COM4');
    expect(
      matcher.matches(
        const DcsDiscoveredDevice(
          id: 'serial:COM4',
          portName: 'COM4',
          transport: DcsDeviceTransport.serial,
        ),
      ),
      isTrue,
    );
    expect(
      matcher.matches(
        const DcsDiscoveredDevice(
          id: 'serial:COM44',
          portName: 'COM44',
          transport: DcsDeviceTransport.serial,
        ),
      ),
      isFalse,
    );
    expect(
      matcher.matches(
        const DcsDiscoveredDevice(
          id: 'serial:COM40',
          portName: 'COM40',
          transport: DcsDeviceTransport.serial,
        ),
      ),
      isFalse,
    );
  });
}

class _FakeAdapter implements DcsDeviceAdapter {
  _FakeAdapter({this.devices = const [], this.failConnects = 0, this.onWrite});

  final List<DcsDiscoveredDevice> devices;
  final int failConnects;
  final void Function(List<int> bytes, StreamController<List<int>> data)? onWrite;

  static int _instanceCounter = 0;
  final int _instanceId = _instanceCounter++;
  static final Map<int, int> _discoverCalls = {};
  static final Map<int, int> _connectCalls = {};

  int get discoverCalls => _discoverCalls[_instanceId] ?? 0;
  int get connectCalls => _connectCalls[_instanceId] ?? 0;

  @override
  DcsDeviceTransport get transport => DcsDeviceTransport.serial;

  @override
  Future<List<DcsDiscoveredDevice>> discover() async {
    _discoverCalls[_instanceId] = discoverCalls + 1;
    return devices;
  }

  @override
  Future<DcsDeviceSession> connect(
    DcsDeviceProfile profile,
    DcsDiscoveredDevice device,
  ) async {
    _connectCalls[_instanceId] = connectCalls + 1;
    if (connectCalls <= failConnects) {
      throw const DcsDeviceConnectionException('Temporary failure.');
    }
    return _FakeSession(onWrite: onWrite);
  }
}

class _FakeSession implements DcsDeviceSession {
  _FakeSession({this.onWrite});

  final void Function(List<int> bytes, StreamController<List<int>> data)? onWrite;
  final _data = StreamController<List<int>>.broadcast();
  var _open = true;

  @override
  Stream<List<int>> get data => _data.stream;

  @override
  bool get isOpen => _open;

  @override
  Future<void> close() async {
    _open = false;
    await _data.close();
  }

  @override
  Future<void> ping() async {
    if (!_open) throw const DcsDeviceConnectionException('Closed.');
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!_open) throw const DcsDeviceConnectionException('Closed.');
    onWrite?.call(bytes, _data);
  }
}

DcsDeviceController _controllerWithProfiles() {
  return DcsDeviceController(
    initialConfig: DcsDeviceConfig(
      profiles: [
        DcsDeviceProfile(
          id: 'boarding-reader',
          label: 'Boarding Reader',
          role: DcsDeviceRole.barcodeReader,
        ),
        DcsDeviceProfile(
          id: 'bag-printer',
          label: 'Bag Printer',
          role: DcsDeviceRole.bagTagPrinter,
        ),
      ],
    ),
    adapters: [_FakeAdapter()],
  );
}
