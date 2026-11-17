import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dcs_cute_peripherals/dcs_cute_peripherals.dart';
import 'package:dcs_cute_peripherals/src/cute_ffi_worker.dart';
import 'package:flutter_test/flutter_test.dart';

// Tasks must be top-level so they can be sent to the worker isolate.

/// Blocks its thread synchronously, like a `PM_WAIT` FFI call.
int _blockFor(int ms) {
  sleep(Duration(milliseconds: ms));
  return ms;
}

int _echo(int value) => value;

int _failWithCode(int code) => throw CutePeripheralFailure('native failed', code: code);

int _throwUnsendable(int _) => throw _UnsendableError();

/// Holds a ReceivePort, which cannot cross isolates, forcing the fallback path.
class _UnsendableError implements Exception {
  final ReceivePort port = ReceivePort();
  @override
  String toString() => 'unsendable error';
}

void main() {
  group('CuteFfiWorker', () {
    late CuteFfiWorker worker;

    setUp(() => worker = CuteFfiWorker(debugName: 'test'));
    tearDown(() => worker.dispose());

    test('a blocking task does not block the calling isolate', () async {
      var ticks = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 20), (_) => ticks++);
      final watch = Stopwatch()..start();
      final result = await worker.run(_blockFor, 400);
      watch.stop();
      timer.cancel();

      expect(result, 400);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(400));
      // On the caller's isolate the timer kept firing while the task slept.
      expect(ticks, greaterThanOrEqualTo(5));
    });

    test('runs calls one at a time in call order', () async {
      final order = <int>[];
      await Future.wait([
        worker.run(_blockFor, 150).then(order.add),
        worker.run(_echo, 1).then(order.add),
        worker.run(_echo, 2).then(order.add),
      ]);
      expect(order, [150, 1, 2]);
    });

    test('rethrows CutePeripheralFailure with its code', () async {
      await expectLater(
        worker.run(_failWithCode, -128),
        throwsA(isA<CutePeripheralFailure>().having((f) => f.code, 'code', -128)),
      );
      // The worker survives a failed task.
      expect(await worker.run(_echo, 7), 7);
    });

    test('an error that cannot be sent arrives as CutePeripheralFailure', () async {
      await expectLater(
        worker.run(_throwUnsendable, 0),
        throwsA(
          isA<CutePeripheralFailure>().having((f) => f.message, 'message', contains('unsendable')),
        ),
      );
    });

    test('dispose fails pending calls and rejects new ones', () async {
      final pending = expectLater(worker.run(_blockFor, 300), throwsA(isA<CutePeripheralFailure>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await worker.dispose();
      await pending;
      await expectLater(worker.run(_echo, 1), throwsA(isA<CutePeripheralFailure>()));
    });
  });

  group('SITA / RESA on a non-Windows host', () {
    const identity = CutePeripheralIdentity(
      kind: CutePeripheralKind.btp,
      name: 'BTP1',
      airlineCode: 'XX',
    );

    test('SitaDevice.open fails with UnsupportedError from the worker, dispose completes', () async {
      final device = SitaDevice(identity: identity);
      await expectLater(device.open(), throwsA(isA<UnsupportedError>()));
      expect(device.currentStatus.state, CutePeripheralState.disconnected);
      await expectLater(device.lock(), throwsA(isA<CutePeripheralFailure>()));
      await device.dispose();
    }, skip: Platform.isWindows ? 'needs a host without xspmapi.dll' : false);

    test('ResaDevice.open fails with UnsupportedError from the worker, dispose completes', () async {
      final device = ResaDevice(identity: identity);
      await expectLater(device.open(), throwsA(isA<UnsupportedError>()));
      await expectLater(device.read(), throwsA(isA<CutePeripheralFailure>()));
      await device.dispose();
    }, skip: Platform.isWindows ? 'needs a host without crwnt_dm.dll' : false);
  });
}
