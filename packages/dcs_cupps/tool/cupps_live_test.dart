import 'dart:io';

import 'package:dcs_cupps/dcs_cupps.dart';

/// End-to-end CUPPS smoke test against a live platform.
///
/// Validates protocol XML (auth, acquire, AEA, print, unlock, bye) more than
/// virtual-hardware readiness — Abomis virtual BP/BT often stay `initializing`.
Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  stdout.writeln('CUPPS E2E test → ${options.host}:${options.port} (${options.airline})');

  final client = CuppsClient(
    options: const CuppsConnectionOptions(requestTimeout: Duration(seconds: 25)),
  );

  var hadFailure = false;

  try {
    await client.connect(
      endpoint: CuppsEndpoint(host: options.host, port: options.port),
      application: CuppsApplicationInfo(
        airlineCode: options.airline,
        applicationName: 'DCS CUPPS Test',
        applicationVersion: '1.0.0',
      ),
    );
    _print('Platform connected.');

    await client.authenticate();
    _print('Authenticated. devices=${client.devices.length}');

    await client.connectDevices();
    await client.initializeDevices(
      deviceToken: client.deviceToken ?? '',
      airlineId: options.airline,
    );

    final plan = CuppsConfigureCommands.virtualPlatformDefaults(
      airlineCode: options.airline,
    );
    await client.configureDevices(plan: plan);
    _print('Configure sequence sent.');

    for (final device in client.devices) {
      final status = client.currentDeviceStatuses[device.id];
      _print(
        '${device.descriptor.name} [${device.descriptor.type.code}] '
        'acquired=${status?.acquired} hardware=${status?.hardwareStatusLabel ?? '-'} '
        'msg=${status?.message}',
      );

      if (status?.acquired != true) {
        hadFailure = true;
        continue;
      }

      if (device.descriptor.type == CuppsDeviceType.boardingPassPrinter ||
          device.descriptor.type == CuppsDeviceType.bagTagPrinter) {
        final aea = await device.aeaRequest(
          'ST#A#B',
          waitForDeviceAck: false,
        );
        _print('  ST#A#B → ok=${aea.ok} result=${aea.result} msg=${aea.message}');
        if (!aea.ok) hadFailure = true;

        final ready = status?.hardwareStatusLabel?.toLowerCase() == 'ready';
        _print('  hardwareReady=$ready (informational on virtual platforms)');
      }

      if (device.descriptor.type == CuppsDeviceType.documentPrinter) {
        final print = await device.print(
          'CUPPS E2E PRINT\n',
          documentId: 'e2e-${device.descriptor.name}',
          stockName: 'A4',
          useAea: false,
        );
        _print('  printRequest → ok=${print.ok} result=${print.result}');
        if (!print.ok) hadFailure = true;
      }

      if (device.supportsDeviceLock) {
        final unlock = await device.unlock();
        _print('  unlock → ok=${unlock.ok}');
        if (!unlock.ok) hadFailure = true;
      }
    }

    await client.disconnect();

    if (hadFailure) {
      _print('PARTIAL — one or more protocol commands failed.');
      exit(2);
    }

    _print('PASS — CUPPS protocol commands completed.');
    exit(0);
  } catch (error, stackTrace) {
    stderr.writeln('FAIL — $error\n$stackTrace');
    try {
      await client.dispose();
    } catch (_) {}
    exit(1);
  }
}

void _print(String message) {
  stdout.writeln('[${DateTime.now().toIso8601String()}] $message');
}

class _Options {
  const _Options({required this.host, required this.port, required this.airline});
  final String host;
  final int port;
  final String airline;
}

_Options _parseArgs(List<String> args) {
  var host = Platform.environment['CUPPS_HOST'] ?? '127.0.0.1';
  var port = int.tryParse(Platform.environment['CUPPS_PORT'] ?? '') ?? 7535;
  var airline = Platform.environment['CUPPS_AIRLINE'] ?? 'IR';

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--host' && i + 1 < args.length) host = args[++i];
    if (arg == '--port' && i + 1 < args.length) port = int.tryParse(args[++i]) ?? port;
    if (arg == '--airline' && i + 1 < args.length) airline = args[++i];
  }

  return _Options(host: host, port: port, airline: airline.toUpperCase());
}
