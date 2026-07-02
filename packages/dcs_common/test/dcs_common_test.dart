import 'dart:io';

import 'package:dcs_common/dcs_common.dart';
import 'package:test/test.dart';

void main() {
  group('runtime contracts', () {
    test('endpoint validates host and port', () {
      expect(const DcsEndpoint(host: '127.0.0.1', port: 4000).isValid, isTrue);
      expect(const DcsEndpoint(host: '', port: 4000).isValid, isFalse);
      expect(const DcsEndpoint(host: '127.0.0.1', port: 70000).isValid, isFalse);
    });

    test('failed status needs attention', () {
      final status = DcsRuntimeStatus.now(
        component: const DcsRuntimeComponent(
          id: 'cupps',
          label: 'CUPPS',
          module: DcsPackageModule.cupps,
        ),
        state: DcsRuntimeState.failed,
        message: 'Failed',
      );

      expect(status.needsAttention, isTrue);
    });

    test('standard log store writes readable and jsonl files', () async {
      final directory = await Directory.systemTemp.createTemp('dcs_common_logs_');
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      final store = DcsStandardLogStore(rootDirectory: directory);
      await store.writeBoth(
        DcsStandardLogEvent.now(
          module: DcsPackageModule.cupps,
          severity: DcsLogSeverity.info,
          operation: 'print',
          deviceId: 'bp-1',
          message: 'Printed boarding pass.',
        ),
      );

      final files = await store.list();
      expect(files, hasLength(2));
      expect(files.map((file) => file.format), containsAll(DcsLogFileFormat.values));
      expect(await store.read(files.first), contains('Printed boarding pass.'));
    });
  });
}
