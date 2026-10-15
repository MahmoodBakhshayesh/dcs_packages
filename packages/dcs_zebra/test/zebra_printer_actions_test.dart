import 'package:dcs_zebra/dcs_zebra.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_zebra_transport.dart';

void main() {
  const descriptor = ZebraPrinterDescriptor(
    id: 'tcp:10.0.0.1:9100',
    address: '10.0.0.1:9100',
    connectionType: ZebraConnectionType.tcp,
    name: 'ZQ620',
    model: 'ZQ620',
  );

  Future<ZebraPrinter> connectedPrinter(FakeZebraTransport transport) async {
    final printer = ZebraPrinter(
      descriptor: descriptor,
      logger: ZebraLogger(),
      onStatus: (_) {},
      options: const ZebraConnectionOptions(autoQueryStatusAfterConnect: false),
      transport: transport,
    );
    await printer.connect();
    return printer;
  }

  group('ZebraPrinterDescriptor discovery fields', () {
    test('parses rssi/paired and computes isMobileModel', () {
      final d = ZebraPrinterDescriptor.fromMap({
        'id': 'bluetooth:AA:BB',
        'address': 'AA:BB:CC:DD:EE:FF',
        'connectionType': 'bluetooth',
        'name': 'Warehouse',
        'model': 'ZQ620',
        'rssi': -67,
        'paired': true,
      });
      expect(d.rssi, -67);
      expect(d.paired, isTrue);
      expect(d.isMobileModel, isTrue);
      expect(
        const ZebraPrinterDescriptor(
          id: 'x',
          address: 'x',
          connectionType: ZebraConnectionType.tcp,
          model: 'ZD421',
        ).isMobileModel,
        isFalse,
      );
      expect(
        const ZebraPrinterDescriptor(
          id: 'x',
          address: 'x',
          connectionType: ZebraConnectionType.bluetooth,
          model: 'iMZ320',
        ).isMobileModel,
        isTrue,
      );
      expect(
        const ZebraPrinterDescriptor(
          id: 'x',
          address: 'x',
          connectionType: ZebraConnectionType.bluetooth,
          model: 'ZR338',
        ).isMobileModel,
        isTrue,
      );
    });
  });

  group('printer actions', () {
    test('calibrate sends ~JC', () async {
      final transport = FakeZebraTransport();
      final printer = await connectedPrinter(transport);
      final result = await printer.calibrate();
      expect(result.ok, isTrue);
      expect(transport.writes.last, contains('~JC'));
    });

    test('printConfigurationLabel sends ~WC', () async {
      final transport = FakeZebraTransport();
      final printer = await connectedPrinter(transport);
      final result = await printer.printConfigurationLabel();
      expect(result.ok, isTrue);
      expect(transport.writes.last, contains('~WC'));
    });

    test('printTestLabel sends small ZPL with text', () async {
      final transport = FakeZebraTransport();
      final printer = await connectedPrinter(transport);
      final result = await printer.printTestLabel(text: 'Hello Gate');
      expect(result.ok, isTrue);
      expect(transport.writes.last, contains('^XA'));
      expect(transport.writes.last, contains('Hello Gate'));
      expect(transport.writes.last, contains('^XZ'));
    });

    test('setDarkness / getDarkness use print.tone SGD', () async {
      final transport = FakeZebraTransport(sgdValues: {'print.tone': '15'});
      final printer = await connectedPrinter(transport);
      final set = await printer.setDarkness(15);
      expect(set.ok, isTrue);
      expect(transport.writes.any((w) => w.contains('setvar "print.tone" "15"')), isTrue);

      final tone = await printer.getDarkness();
      expect(tone, 15);
      expect(transport.writes.any((w) => w.contains('getvar "print.tone"')), isTrue);
    });

    test('setSpeed / getSpeed use media.speed SGD', () async {
      final transport = FakeZebraTransport(sgdValues: {'media.speed': '4'});
      final printer = await connectedPrinter(transport);
      await printer.setSpeed(4);
      expect(transport.writes.any((w) => w.contains('setvar "media.speed" "4"')), isTrue);
      expect(await printer.getSpeed(), 4);
    });

    test('batteryPercent parses power.percent_full and nulls empty', () async {
      final transport = FakeZebraTransport(
        sgdValues: {'power.percent_full': '82'},
      );
      final printer = await connectedPrinter(transport);
      expect(await printer.batteryPercent(), 82);

      transport.sgdValues['power.percent_full'] = '';
      expect(await printer.batteryPercent(), isNull);
    });
  });

  group('printBatch', () {
    test('emits queued/sending/done progress', () async {
      final transport = FakeZebraTransport();
      final printer = await connectedPrinter(transport);
      final jobs = [
        const ZebraJob(id: 'j1', data: '^XA^FDOne^FS^XZ'),
        const ZebraJob(id: 'j2', data: '^XA^FDTwo^FS^XZ'),
      ];
      final events = await printer
          .printBatch(jobs, waitForReady: false)
          .toList();

      expect(
        events.map((e) => '${e.jobId}:${e.state.name}'),
        [
          'j1:queued',
          'j1:sending',
          'j1:done',
          'j2:queued',
          'j2:sending',
          'j2:done',
        ],
      );
      expect(transport.writes.where((w) => w.contains('^XA')).length, 2);
    });

    test('records failed jobs and supports retry', () async {
      final transport = FakeZebraTransport();
      transport.failWritesMatching.add('FAILME');
      final printer = await connectedPrinter(transport);
      final jobs = [
        const ZebraJob(id: 'ok', data: '^XA^FDok^FS^XZ'),
        const ZebraJob(id: 'bad', data: '^XA^FDFAILME^FS^XZ'),
      ];
      final events = await printer
          .printBatch(jobs, waitForReady: false)
          .toList();
      expect(events.where((e) => e.state == ZebraJobState.failed).single.jobId, 'bad');
      expect(printer.lastFailedJobs.map((j) => j.id), ['bad']);

      transport.failWritesMatching.clear();
      final retry = await printer.retryFailedJobs(waitForReady: false).toList();
      expect(retry.last.state, ZebraJobState.done);
      expect(retry.last.jobId, 'bad');
    });

    test('cancelBatch stops remaining jobs', () async {
      final transport = FakeZebraTransport();
      final printer = await connectedPrinter(transport);
      final jobs = List.generate(
        5,
        (i) => ZebraJob(id: 'j$i', data: '^XA^FD$i^FS^XZ'),
      );

      final events = <ZebraJobProgress>[];
      await for (final event in printer.printBatch(jobs, waitForReady: false)) {
        events.add(event);
        if (event.jobId == 'j0' && event.state == ZebraJobState.done) {
          printer.cancelBatch();
        }
      }
      expect(events.any((e) => e.jobId == 'j4'), isFalse);
      expect(transport.writes.where((w) => w.contains('^XA')).length, lessThan(5));
    });

    test('maxRetries re-sends failed job', () async {
      final transport = FakeZebraTransport();
      final printer = await connectedPrinter(transport);
      transport.failNextWrite = true;

      final events = await printer
          .printBatch(
            [const ZebraJob(id: 'r1', data: '^XA^FDretry^FS^XZ')],
            waitForReady: false,
            maxRetries: 1,
          )
          .toList();

      expect(events.where((e) => e.state == ZebraJobState.sending).length, 2);
      expect(events.last.state, ZebraJobState.done);
    });
  });
}
