import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dcs_cute/dcs_cute.dart';

void main() {
  test('MATIP decoder handles partial and batched packets', () {
    const codec = CuteMatipCodec();
    const config = CuteSessionConfig();
    final decoder = CuteMatipDecoder();
    final first = codec.textData(config, text: 'ONE');
    final second = codec.textData(config, text: 'TWO');
    final bytes = [...first, ...second];

    decoder.add(bytes.take(3).toList());
    expect(decoder.takePackets(), isEmpty);

    decoder.add(bytes.skip(3).take(8).toList());
    expect(decoder.takePackets(), hasLength(1));

    decoder.add(bytes.skip(11).toList());
    final packets = decoder.takePackets();
    expect(packets, hasLength(1));
    expect(codec.decodeData(config, packets.single).text, 'TWO');
  });

  test('session config rejects incoherent multiplex/header combinations', () {
    const config = CuteSessionConfig(
      multiplexMode: CuteMultiplexMode.groupWithFourByteAscu,
      addressHeader: CuteAddressHeader.none,
    );

    expect(config.validate, throwsA(isA<CuteConfigurationFailure>()));
  });

  test('certification rules warn on non-standard MATIP port', () {
    final findings = const CuteCertificationRules().evaluate(
      const CuteCertificationProfile(
        endpoint: CuteEndpoint(host: '127.0.0.1', port: 12345),
        session: CuteSessionConfig(),
      ),
    );

    expect(
      findings
          .where((finding) => finding.id == 'CUTE-MATIP-002')
          .single
          .severity,
      CuteRuleSeverity.warning,
    );
    expect(findings.any((finding) => finding.isBlocking), isFalse);
  });

  test('client opens session and emits inbound host payloads', () async {
    final transport = FakeCuteTransport();
    final client = CuteClient(transportFactory: () => transport);
    const config = CuteSessionConfig();

    final connectFuture = client.connect(
      endpoint: const CuteEndpoint(host: '127.0.0.1', port: 350),
      config: config,
    );

    final sessionOpen = (await transport.takeWrittenPackets()).single;
    expect(sessionOpen.command, CuteMatipCommand.sessionOpen);
    transport.addInbound(const CuteMatipCodec().openConfirmAccepted(config));
    await connectFuture;
    expect(client.isOpen, isTrue);

    final messageFuture = client.messages.first;
    transport.addInbound(
      const CuteMatipCodec().textData(config, text: 'HELLO'),
    );
    expect((await messageFuture).text, 'HELLO');

    await client.sendText('ACK');
    final outbound = (await transport.takeWrittenPackets()).single;
    expect(outbound.command, CuteMatipCommand.data);
    expect(const CuteMatipCodec().decodeData(config, outbound).text, 'ACK');

    await client.dispose();
  });
}

class FakeCuteTransport implements CuteTransport {
  final _incoming = StreamController<List<int>>.broadcast();
  final _writtenSignal = StreamController<void>.broadcast();
  final _written = <List<int>>[];
  final _decoder = CuteMatipDecoder();
  var _open = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  bool get isOpen => _open;

  @override
  Future<void> connect(
    CuteEndpoint endpoint, {
    required Duration timeout,
  }) async {
    _open = true;
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!_open) {
      throw const CuteProtocolFailure('Fake transport is closed.');
    }
    _written.add(List<int>.of(bytes));
    _writtenSignal.add(null);
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  void addInbound(List<int> bytes) {
    _incoming.add(List<int>.of(bytes));
  }

  Future<List<CuteMatipPacket>> takeWrittenPackets() async {
    if (_written.isEmpty) {
      await _writtenSignal.stream.first.timeout(const Duration(seconds: 1));
    }
    final written = List<List<int>>.of(_written);
    _written.clear();
    for (final chunk in written) {
      _decoder.add(chunk);
    }
    return _decoder.takePackets();
  }
}
