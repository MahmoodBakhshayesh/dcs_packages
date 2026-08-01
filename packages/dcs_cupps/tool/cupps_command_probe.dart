import 'dart:io';

import 'package:dcs_cupps/dcs_cupps.dart';

const _aeaCommand = 'EP#AIRLINEID=IR#HARDCODE=HDC#FONT=L';
const _printDocument = 'CUPPS PRINT PROBE\n';

CuppsDevice? _findDevice(List<CuppsDevice> devices, CuppsDeviceType type) {
  for (final device in devices) {
    if (device.descriptor.type == type) return device;
  }
  return null;
}

void _printResult(String label, CuppsCommandResult result) {
  stdout.writeln('');
  stdout.writeln('=== $label result ===');
  stdout.writeln('ok=${result.ok} result=${result.result} message=${result.message}');
  if (result.rawXml.isNotEmpty) {
    stdout.writeln('rawXml:\n${result.rawXml}');
  }
}

void _printLoggerEvents(
  CuppsLogger logger, {
  required String label,
  bool Function(CuppsLogEvent event)? matches,
}) {
  final events = logger.recent.where((event) {
    if (matches != null) return matches(event);
    return (event.xml != null && event.xml!.isNotEmpty) ||
        event.scope == CuppsLogScope.protocol ||
        event.scope == CuppsLogScope.socket;
  }).toList(growable: false);

  stdout.writeln('');
  stdout.writeln('=== Logger events ($label) ===');
  if (events.isEmpty) {
    stdout.writeln('(no matching events)');
    return;
  }

  var index = 0;
  for (final event in events) {
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
  stdout.writeln('Total matching events: ${events.length}');
}

bool _isPrintRequestEvent(CuppsLogEvent event) {
  final xml = event.xml;
  if (xml == null || xml.isEmpty) return false;
  return xml.contains('<printRequest') ||
      xml.contains('printRequestResponse') ||
      event.message.toLowerCase().contains('printrequest');
}

Future<void> main() async {
  stdout.writeln('=== CUPPS command probe → 127.0.0.1:7535 (IR) ===');

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
        applicationName: 'DCS Command Probe',
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

    final bp = _findDevice(client.devices, CuppsDeviceType.boardingPassPrinter);
    if (bp == null) {
      throw StateError('No boarding pass printer (BP) device found.');
    }

    stdout.writeln('');
    stdout.writeln('BP device: ${bp.descriptor.name} [${bp.descriptor.type.code}]');
    stdout.writeln(
      'Status: acquired=${bp.status?.acquired} '
      'initialized=${bp.status?.initialized} '
      'hardware=${bp.status?.hardwareStatusLabel ?? '-'}',
    );

    stdout.writeln('');
    stdout.writeln('Sending aeaRequest: $_aeaCommand');
    stdout.writeln('  waitForDeviceAck=false');

    final bpResult = await bp.aeaRequest(
      _aeaCommand,
      waitForDeviceAck: false,
      timeout: const Duration(seconds: 20),
    );
    _printResult('BP aeaRequest', bpResult);

    _printLoggerEvents(
      logger,
      label: 'BP aeaRequest (outbound/response xml)',
      matches: (event) {
        final xml = event.xml;
        if (xml == null || xml.isEmpty) return false;
        return xml.contains('<aeaRequest') ||
            xml.contains('aeaRequestResponse') ||
            xml.contains(_aeaCommand);
      },
    );

    final pr = _findDevice(client.devices, CuppsDeviceType.documentPrinter);
    if (pr == null) {
      throw StateError('No document printer (PR) device found.');
    }

    stdout.writeln('');
    stdout.writeln('PR device: ${pr.descriptor.name} [${pr.descriptor.type.code}]');
    stdout.writeln(
      'Status: acquired=${pr.status?.acquired} '
      'initialized=${pr.status?.initialized} '
      'hardware=${pr.status?.hardwareStatusLabel ?? '-'}',
    );

    stdout.writeln('');
    stdout.writeln(
      'Sending printRequest via device.print(useAea: false, '
      "document: '$_printDocument', documentId: 'probe-1', stockName: 'A4')",
    );

    final printEventCountBefore = logger.recent.length;
    final prResult = await pr.print(
      _printDocument,
      documentId: 'probe-1',
      stockName: 'A4',
      useAea: false,
      timeout: const Duration(seconds: 20),
    );
    _printResult('PR printRequest', prResult);

    final printLoggerEvents = logger.recent
        .skip(printEventCountBefore)
        .where(_isPrintRequestEvent)
        .toList(growable: false);
    stdout.writeln('');
    stdout.writeln('=== Logger events (PR printRequest outbound + response) ===');
    if (printLoggerEvents.isEmpty) {
      stdout.writeln('(no matching events)');
    } else {
      var index = 0;
      for (final event in printLoggerEvents) {
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
      stdout.writeln('Total matching events: ${printLoggerEvents.length}');
    }

    await client.disconnect();
    stdout.writeln('');
    stdout.writeln('Disconnected.');
  } catch (error, stackTrace) {
    stderr.writeln('');
    stderr.writeln('FAIL: $error');
    stderr.writeln(stackTrace);

    _printLoggerEvents(
      logger,
      label: 'failure (xml or protocol/socket)',
    );

    try {
      await client.dispose();
    } catch (_) {}
    exit(1);
  }
}
