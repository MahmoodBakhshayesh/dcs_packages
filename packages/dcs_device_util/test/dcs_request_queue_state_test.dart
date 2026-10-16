import 'dart:async';

import 'package:dcs_device_util/dcs_device_util.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every write with `OK` after [delay].
class _EchoSession implements DcsDeviceSession {
  static const delay = Duration(milliseconds: 20);
  final _data = StreamController<List<int>>.broadcast();
  final writes = <String>[];

  @override
  Stream<List<int>> get data => _data.stream;

  @override
  bool get isOpen => true;

  @override
  Future<void> write(List<int> bytes) async {
    writes.add(String.fromCharCodes(bytes));
    Timer(delay, () => _data.add('OK'.codeUnits));
  }

  @override
  Future<void> ping() async {}

  @override
  Future<void> close() async => _data.close();
}

void main() {
  const options = DcsDeviceRequestOptions(
    timeout: Duration(seconds: 1),
    quietWindow: Duration(milliseconds: 5),
  );

  test('queue reports waiting / running and calls onStart in order', () async {
    final session = _EchoSession();
    final queue = DcsDeviceRequestQueue(session, defaultOptions: options);
    final states = <DcsQueueState>[];
    final sub = queue.states.listen(states.add);
    final started = <String>[];

    final a = queue.sendText('A', onStart: () => started.add('A'));
    final b = queue.sendText('B', onStart: () => started.add('B'));
    final c = queue.sendText('C', onStart: () => started.add('C'));

    // All three enqueued before the first starts.
    expect(states.take(3).map((s) => s.waiting), [1, 2, 3]);
    expect(started, isEmpty);

    await a;
    // B may already be on the wire; C still waits behind it.
    expect(started.first, 'A');
    expect(started, isNot(contains('C')));
    expect(queue.state.waiting, lessThanOrEqualTo(1));

    await Future.wait([b, c]);
    expect(started, ['A', 'B', 'C']);
    expect(session.writes, ['A', 'B', 'C']);
    expect(queue.state.isIdle, isTrue);
    // Strictly serial: never more than one running.
    expect(states.every((s) => s.running <= 1), isTrue);
    await sub.cancel();
  });

  test('onStart errors do not break the queue', () async {
    final queue = DcsDeviceRequestQueue(_EchoSession(), defaultOptions: options);
    final r = await queue.sendText('X', onStart: () => throw StateError('observer'));
    expect(r.isOk, isTrue);
    expect(queue.state.isIdle, isTrue);
  });

  test('onStateChanged mirrors the state stream', () async {
    final seen = <DcsQueueState>[];
    final queue = DcsDeviceRequestQueue(_EchoSession(), defaultOptions: options, onStateChanged: seen.add);
    await queue.sendText('A');
    expect(seen.first, const DcsQueueState(waiting: 1));
    expect(seen.last, const DcsQueueState());
  });
}
