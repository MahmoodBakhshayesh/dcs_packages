import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dcs_device_util/dcs_device_util.dart';

void main() {
  testWidgets('controller status list renders configured devices', (
    tester,
  ) async {
    final controller = _controllerWithProfiles();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DcsDeviceControllerStatusList(controller: controller),
        ),
      ),
    );

    expect(find.text('Boarding Reader'), findsOneWidget);
    expect(find.text('Bag Printer'), findsOneWidget);

    await controller.dispose();
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

    expect(find.byType(DcsDeviceStatusCard), findsNWidgets(2));
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
    expect(
      DcsDeviceStatusAssets.pathFor(
        kind: DcsDeviceKind.reader,
        state: DcsDeviceConnectionState.retrying,
      ),
      'assets/devices/dcs_reader_warning.png',
    );
    expect(
      DcsDeviceStatusAssets.pathFor(
        kind: DcsDeviceKind.unknown,
        state: DcsDeviceConnectionState.failed,
      ),
      'assets/devices/dcs_usb_error.png',
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
      initialConfig: const DcsDeviceConfig(
        profiles: [
          DcsDeviceProfile(
            id: 'boarding-reader',
            label: 'Boarding Reader',
            kind: DcsDeviceKind.reader,
            matcher: DcsDeviceMatcher(portName: 'COM7'),
          ),
        ],
      ),
      adapters: [adapter],
      healthPolicy: const DcsConnectionHealthPolicy(
        heartbeatInterval: Duration(minutes: 1),
      ),
    );

    await controller.start();

    expect(adapter.discoverCalls, 1);
    expect(adapter.connectCalls, 1);
    expect(
      controller.currentStatuses['boarding-reader']?.state,
      DcsDeviceConnectionState.connected,
    );

    await controller.dispose();
  });

  test('retries transient connection failures', () async {
    final adapter = _FakeAdapter(
      failConnects: 1,
      devices: const [
        DcsDiscoveredDevice(
          id: 'serial:COM9',
          portName: 'COM9',
          transport: DcsDeviceTransport.serial,
        ),
      ],
    );

    final controller = DcsDeviceController(
      initialConfig: const DcsDeviceConfig(
        profiles: [
          DcsDeviceProfile(
            id: 'bag-printer',
            label: 'Bag Printer',
            kind: DcsDeviceKind.printer,
            matcher: DcsDeviceMatcher(portName: 'COM9'),
          ),
        ],
      ),
      adapters: [adapter],
      retryPolicy: const DcsRetryPolicy(
        maxAttempts: 2,
        initialDelay: Duration.zero,
        maxDelay: Duration.zero,
      ),
      healthPolicy: const DcsConnectionHealthPolicy(
        heartbeatInterval: Duration(minutes: 1),
      ),
    );

    await controller.start();

    expect(adapter.connectCalls, 2);
    expect(
      controller.currentStatuses['bag-printer']?.state,
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
      initialConfig: const DcsDeviceConfig(
        profiles: [
          DcsDeviceProfile(
            id: 'reader',
            label: 'Reader',
            kind: DcsDeviceKind.reader,
            matcher: DcsDeviceMatcher(portName: 'COM10'),
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
      'reader',
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

  test('returns timeout when request receives no payload', () async {
    final session = _FakeSession();
    final queue = DcsDeviceRequestQueue(session);

    final response = await queue.sendText(
      'AV',
      options: const DcsDeviceRequestOptions(
        timeout: Duration(milliseconds: 1),
      ),
    );

    expect(response.status, DcsDeviceResponseStatus.timeout);
    expect(response.timedOut, isTrue);

    await session.close();
  });

  test('persists and reloads device configuration', () async {
    final store = _MemoryConfigStore();
    const config = DcsDeviceConfig(
      autoReconnect: false,
      profiles: [
        DcsDeviceProfile(
          id: 'passport-reader',
          label: 'Passport Reader',
          kind: DcsDeviceKind.reader,
          matcher: DcsDeviceMatcher(productName: 'Passport'),
        ),
      ],
    );

    final writer = DcsDeviceController(
      initialConfig: config,
      configStore: store,
      adapters: [_FakeAdapter()],
    );
    await writer.saveConfig(config);
    await writer.dispose();

    final reader = DcsDeviceController(
      configStore: store,
      adapters: [_FakeAdapter()],
    );
    await reader.start(connect: false);

    expect(reader.config.profiles.single.id, 'passport-reader');
    expect(reader.config.autoReconnect, isFalse);

    await reader.dispose();
  });
}

class _FakeAdapter implements DcsDeviceAdapter {
  _FakeAdapter({this.devices = const [], this.failConnects = 0, this.onWrite});

  final List<DcsDiscoveredDevice> devices;
  final int failConnects;
  final void Function(List<int> bytes, StreamController<List<int>> data)?
  onWrite;

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

  final void Function(List<int> bytes, StreamController<List<int>> data)?
  onWrite;
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
    if (!_open) {
      throw const DcsDeviceConnectionException('Closed.');
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!_open) {
      throw const DcsDeviceConnectionException('Closed.');
    }
    onWrite?.call(bytes, _data);
  }
}

class _MemoryConfigStore implements DcsConfigStore {
  DcsDeviceConfig? value;

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<DcsDeviceConfig?> load() async => value;

  @override
  Future<void> save(DcsDeviceConfig config) async {
    value = config;
  }
}

DcsDeviceController _controllerWithProfiles() {
  return DcsDeviceController(
    initialConfig: const DcsDeviceConfig(
      profiles: [
        DcsDeviceProfile(
          id: 'boarding-reader',
          label: 'Boarding Reader',
          kind: DcsDeviceKind.reader,
        ),
        DcsDeviceProfile(
          id: 'bag-printer',
          label: 'Bag Printer',
          kind: DcsDeviceKind.printer,
        ),
      ],
    ),
    adapters: [_FakeAdapter()],
  );
}
