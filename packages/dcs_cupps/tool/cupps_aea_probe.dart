import 'dart:io';

import 'package:dcs_cupps/dcs_cupps.dart';

const _aeaCommand = 'EP#AIRLINEID=IR#HARDCODE=HDC#FONT=L';

Future<void> main() async {
  stdout.writeln('=== CuppsXml.aeaRequest(messageId: 9, command: ...) ===');
  stdout.writeln(
    CuppsXml.aeaRequest(messageId: 9, command: _aeaCommand),
  );

  stdout.writeln('');
  stdout.writeln('=== CuppsXml.byeRequest(messageId: 1) ===');
  stdout.writeln(CuppsXml.byeRequest(messageId: 1));

  stdout.writeln('');
  stdout.writeln('=== Live CUPPS probe → 127.0.0.1:7535 (IR) ===');

  final logger = CuppsLogger(minimumLevel: CuppsLogLevel.debug);
  final client = CuppsClient(
    logger: logger,
    options: const CuppsConnectionOptions(requestTimeout: Duration(seconds: 25)),
  );

  try {
    await client.connect(
      endpoint: const CuppsEndpoint(host: '127.0.0.1', port: 7535),
      application: const CuppsApplicationInfo(
        airlineCode: 'IR',
        applicationName: 'DCS AEA Probe',
        applicationVersion: '1.0.0',
      ),
    );
    stdout.writeln('Platform connected.');

    await client.authenticate();
    stdout.writeln(
      'Authenticated. devices=${client.devices.length} '
      'token=${client.deviceToken ?? '(none)'}',
    );

    await client.connectDevices();
    stdout.writeln('Device sockets connected.');

    await client.initializeDevices(
      deviceToken: client.deviceToken ?? '',
      airlineId: 'IR',
    );
    stdout.writeln('Devices initialized.');

    final bp = client.devices.cast<CuppsDevice?>().firstWhere(
      (d) => d!.descriptor.type == CuppsDeviceType.boardingPassPrinter,
      orElse: () => null,
    );
    if (bp == null) {
      throw StateError('No boarding pass printer (BP) device found.');
    }

    stdout.writeln('');
    stdout.writeln('BP device: ${bp.descriptor.name} [${bp.descriptor.type.code}]');
    stdout.writeln('Status: acquired=${bp.status?.acquired} '
        'initialized=${bp.status?.initialized} '
        'hardware=${bp.status?.hardwareStatusLabel ?? '-'}');

    stdout.writeln('');
    stdout.writeln('Sending aeaRequest: $_aeaCommand');
    stdout.writeln('  waitForDeviceAck=true (tolerateMissingDeviceAck not on aeaRequest API)');

    final result = await bp.aeaRequest(
      _aeaCommand,
      waitForDeviceAck: true,
      timeout: const Duration(seconds: 20),
    );

    stdout.writeln('');
    stdout.writeln('=== aeaRequest result ===');
    stdout.writeln('ok=${result.ok} result=${result.result} message=${result.message}');
    if (result.rawXml.isNotEmpty) {
      stdout.writeln('rawXml:\n${result.rawXml}');
    }

    stdout.writeln('');
    stdout.writeln('=== Logger events (xml or protocol/socket) ===');
    final protocolEvents = logger.recent.where(
      (event) =>
          (event.xml != null && event.xml!.isNotEmpty) ||
          event.scope == CuppsLogScope.protocol ||
          event.scope == CuppsLogScope.socket,
    );

    if (protocolEvents.isEmpty) {
      stdout.writeln('(no matching events)');
    } else {
      var index = 0;
      for (final event in protocolEvents) {
        index++;
        stdout.writeln('');
        stdout.writeln('--- event $index ---');
        stdout.writeln(
          '${event.timestamp.toIso8601String()} '
          '${event.level.name} '
          '${event.scope.name} '
          '${event.direction.name}',
        );
        stdout.writeln('message: ${event.message}');
        if (event.deviceId != null) stdout.writeln('deviceId: ${event.deviceId}');
        if (event.messageId != null) stdout.writeln('messageId: ${event.messageId}');
        if (event.data.isNotEmpty) stdout.writeln('data: ${event.data}');
        if (event.error != null) stdout.writeln('error: ${event.error}');
        if (event.xml != null && event.xml!.isNotEmpty) {
          stdout.writeln('xml:\n${event.xml}');
        }
      }
      stdout.writeln('');
      stdout.writeln('Total matching events: ${protocolEvents.length}');
    }

    await client.disconnect();
    stdout.writeln('');
    stdout.writeln('Disconnected.');
  } catch (error, stackTrace) {
    stderr.writeln('');
    stderr.writeln('FAIL: $error');
    stderr.writeln(stackTrace);

    stderr.writeln('');
    stderr.writeln('=== Logger events on failure (xml or protocol/socket) ===');
    for (final event in logger.recent.where(
      (e) =>
          (e.xml != null && e.xml!.isNotEmpty) ||
          e.scope == CuppsLogScope.protocol ||
          e.scope == CuppsLogScope.socket,
    )) {
      stderr.writeln(
        '${event.timestamp.toIso8601String()} ${event.level.name} '
        '${event.scope.name} ${event.direction.name}: ${event.message}',
      );
      if (event.xml != null && event.xml!.isNotEmpty) {
        stderr.writeln('xml:\n${event.xml}');
      }
    }

    try {
      await client.dispose();
    } catch (_) {}
    exit(1);
  }
}
