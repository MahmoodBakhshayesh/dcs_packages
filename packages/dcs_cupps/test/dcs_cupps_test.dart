import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dcs_cupps/dcs_cupps.dart';

void main() {
  test('frame decoder handles partial and batched socket chunks', () {
    const codec = CuppsFrameCodec();
    final decoder = CuppsFrameDecoder();
    final first = codec.encode('<cupps messageID="1" messageName="one"/>');
    final second = codec.encode('<cupps messageID="2" messageName="two"/>');
    final bytes = [...first, ...second];

    decoder.add(bytes.take(7).toList());
    expect(decoder.takeFrames(), isEmpty);

    decoder.add(bytes.skip(7).take(20).toList());
    expect(decoder.takeFrames(), isEmpty);

    decoder.add(bytes.skip(27).toList());
    expect(decoder.takeFrames(), [
      '<cupps messageID="1" messageName="one"/>',
      '<cupps messageID="2" messageName="two"/>',
    ]);
  });

  test('authenticate response parser exposes supported devices', () {
    final devices = CuppsXml.devicesFromAuthenticateResponse('''
<?xml version="1.0" encoding="utf-8"?>
<cupps xmlns="$cuppsNamespace" xmlns:xsi="$cuppsXsiNamespace" messageID="3" messageName="authenticateResponse">
  <authenticateResponse result="ok" deviceToken="1234567890123456">
    <deviceList>
      <device deviceIndex="1" deviceName="BP1" deviceParameterType="bpDeviceParameter">
        <supportedInterfaceModes><interfaceMode mode="AEA"/></supportedInterfaceModes>
        <bpDeviceParameter ipAndPort="127.0.0.1:5001" status="ready"/>
      </device>
      <device deviceIndex="1.1" deviceName="BP1-child" deviceParameterType="bpDeviceParameter">
        <bpDeviceParameter ipAndPort="127.0.0.1:5002"/>
      </device>
    </deviceList>
  </authenticateResponse>
</cupps>
''');

    expect(devices, hasLength(1));
    expect(devices.single.type, CuppsDeviceType.boardingPassPrinter);
    expect(devices.single.endpoint.toString(), '127.0.0.1:5001');
    expect(devices.single.supportedInterfaceModes, ['AEA']);
  });

  test('client correlates a platform request by message id', () async {
    final transport = FakeCuppsTransport();
    final client = CuppsClient(transportFactory: () => transport);

    await client.connect(
      endpoint: const CuppsEndpoint(host: '127.0.0.1', port: 4000),
      application: const CuppsApplicationInfo(
        airlineCode: 'ZZ',
        applicationName: 'DCS',
        applicationVersion: '1.0.0',
      ),
    );

    final future = client.sendPlatformRequest(
      (messageId) => CuppsXml.deviceQueryRequest(messageId: messageId),
    );

    final request = transport.takeWrittenXml().single;
    final envelope = CuppsXml.parseEnvelope(request);
    expect(envelope.messageName, 'deviceQueryRequest');

    transport.addInboundXml(
      responseXml(envelope.messageId, 'deviceQueryResponse', 'ok'),
    );

    final result = await future;
    expect(result.ok, isTrue);
    await client.dispose();
  });

  test('logger stores recent structured events', () {
    final logger = CuppsLogger();
    logger(
      CuppsLogLevel.info,
      CuppsLogScope.platform,
      'Platform connected.',
      data: {'state': CuppsPlatformState.connected.name},
    );

    expect(logger.recent, hasLength(1));
    expect(logger.recent.single.scope, CuppsLogScope.platform);
    expect(
      logger.recent.single.toJson(),
      containsPair('message', 'Platform connected.'),
    );
  });

  test('status asset resolver matches generated png schema', () {
    expect(
      CuppsStatusAssets.forDeviceType(
        CuppsDeviceType.boardingPassPrinter,
        CuppsDeviceVisualStatus.paperOut,
      ),
      'assets/images/icons/bp/bp_paper_out.png',
    );
    expect(
      CuppsStatusAssets.forDeviceType(
        CuppsDeviceType.unknown,
        CuppsDeviceVisualStatus.active,
      ),
      'assets/images/icons/unknown.png',
    );
  });

  test('all generated status png assets exist', () {
    final files = Directory('assets/images/icons')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.png'))
        .toList();

    expect(files, hasLength(144));
    expect(File('assets/images/icons/bp/bp_active.png').existsSync(), isTrue);
    expect(
      File('assets/images/icons/zi/zi_disconnect.png').existsSync(),
      isTrue,
    );
    expect(File('assets/images/icons/unknown.png').existsSync(), isTrue);
  });
}

String responseXml(int messageId, String messageName, String result) {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<cupps xmlns="$cuppsNamespace" xmlns:xsi="$cuppsXsiNamespace" messageID="$messageId" messageName="$messageName">
  <$messageName result="$result"/>
</cupps>
''';
}

class FakeCuppsTransport implements CuppsTransport {
  final _incoming = StreamController<List<int>>.broadcast();
  final _written = <List<int>>[];
  final _codec = const CuppsFrameCodec();
  var _open = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  bool get isOpen => _open;

  @override
  Future<void> connect(
    CuppsEndpoint endpoint, {
    required Duration timeout,
  }) async {
    _open = true;
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!_open) {
      throw const CuppsRequestFailure('Fake transport is closed.');
    }
    _written.add(List<int>.of(bytes));
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  void addInboundXml(String xml) {
    _incoming.add(_codec.encode(xml));
  }

  List<String> takeWrittenXml() {
    final written = List<List<int>>.of(_written);
    _written.clear();
    final decoder = CuppsFrameDecoder();
    for (final chunk in written) {
      decoder.add(chunk);
    }
    return decoder.takeFrames();
  }
}
