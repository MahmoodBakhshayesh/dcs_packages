import 'dart:io';

import 'package:dcs_cupps/dcs_cupps.dart';

/// Debug deviceStatusRequest against one connected printer.
Future<void> main() async {
  final logger = CuppsLogger(minimumLevel: CuppsLogLevel.debug);
  final client = CuppsClient(
    logger: logger,
    options: const CuppsConnectionOptions(requestTimeout: Duration(seconds: 30)),
  );

  try {
    await client.connect(
      endpoint: const CuppsEndpoint(host: '127.0.0.1', port: 7535),
      application: const CuppsApplicationInfo(
        airlineCode: 'IR',
        applicationName: 'DCS Status Debug',
        applicationVersion: '1.0.0',
      ),
    );
    await client.authenticate();
    await client.connectDevices();

    final bp = client.devices.firstWhere(
      (d) => d.descriptor.type == CuppsDeviceType.boardingPassPrinter,
    );

    stdout.writeln('BP device: ${bp.descriptor.name}');
    await bp.acquire(deviceToken: client.deviceToken ?? '', airlineId: 'IR');
    stdout.writeln('Acquire done: ${bp.status?.acquired} ${bp.status?.message}');

    await bp.interfaceMode();
    stdout.writeln('Mode done: ${bp.status?.initialized} ${bp.status?.message}');

    stdout.writeln('Sending deviceStatusRequest...');
    try {
      final status = await bp.refreshStatus();
      stdout.writeln('Status ok=${status.ok} result=${status.result} msg=${status.message}');
      stdout.writeln('RAW:\n${status.rawXml}');
    } catch (error) {
      stderr.writeln('Status failed: $error');
      stderr.writeln('Recent logs:');
      for (final event in logger.recent.takeLast(15)) {
        stderr.writeln('  ${event.level.name} ${event.scope.name}: ${event.message}');
        if (event.xml != null && event.xml!.isNotEmpty) {
          stderr.writeln('    XML: ${event.xml}');
        }
      }
    }

    await client.disconnect();
  } catch (error, stackTrace) {
    stderr.writeln('FAIL: $error\n$stackTrace');
    try {
      await client.dispose();
    } catch (_) {}
    exit(1);
  }
}

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}
