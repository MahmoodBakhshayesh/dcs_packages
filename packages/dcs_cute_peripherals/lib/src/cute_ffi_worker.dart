import 'dart:async';
import 'dart:isolate';

import 'models.dart';

/// Runs blocking FFI calls (SITA `XSPM*`, RESA `CRW_DM_*`) on a long-lived
/// background isolate so a native wait never freezes the UI isolate.
///
/// - One worker per device: a device stuck in a native wait does not block the
///   others.
/// - Calls run one at a time in the order they were made (same ordering the
///   device had when every call ran on the UI isolate).
/// - A task is a **top-level or static** function plus a sendable argument
///   (ints, strings, lists, records). Pointers, `DynamicLibrary` and the
///   bindings objects cannot cross isolates: load the bindings and allocate
///   native memory inside the task.
/// - Errors thrown by a task are rethrown in the caller with the same type when
///   they can be sent ([CutePeripheralFailure], [UnsupportedError], …);
///   anything else arrives as a [CutePeripheralFailure] with its text.
///
/// Note: Dart does not pin an isolate to one OS thread. If a vendor DLL
/// requires every call for a handle to come from the same thread, this is not
/// enough and a native worker thread is needed instead.
class CuteFfiWorker {
  CuteFfiWorker({this.debugName = 'cute-ffi'});

  final String debugName;

  Future<SendPort>? _sendPort;
  Isolate? _isolate;
  ReceivePort? _replies;
  ReceivePort? _exits;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Runs `task(arg)` on the worker isolate and returns its result.
  Future<R> run<A, R>(R Function(A arg) task, A arg) async {
    if (_disposed) {
      throw const CutePeripheralFailure('CUTE FFI worker is disposed');
    }
    final port = await (_sendPort ??= _spawn());
    if (_disposed) {
      throw const CutePeripheralFailure('CUTE FFI worker is disposed');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      port.send(_Job<A, R>(id, task, arg));
    } catch (e) {
      _pending.remove(id);
      throw CutePeripheralFailure('CUTE FFI task could not be sent to the worker: $e');
    }
    final result = await completer.future;
    return result as R;
  }

  /// Fails every pending call and kills the worker isolate. A task blocked in a
  /// native call keeps its OS thread until that call returns; nothing waits on it.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failAll(const CutePeripheralFailure('CUTE FFI worker was disposed'));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _replies?.close();
    _exits?.close();
    _replies = null;
    _exits = null;
    _sendPort = null;
  }

  Future<SendPort> _spawn() async {
    final replies = ReceivePort('$debugName-replies');
    final exits = ReceivePort('$debugName-exit');
    _replies = replies;
    _exits = exits;
    final ready = Completer<SendPort>();

    replies.listen((Object? message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is _Reply) {
        final completer = _pending.remove(message.id);
        if (completer == null || completer.isCompleted) return;
        if (message.ok) {
          completer.complete(message.value);
        } else {
          completer.completeError(
            message.value ?? const CutePeripheralFailure('CUTE FFI task failed'),
            message.stack == null ? null : StackTrace.fromString(message.stack!),
          );
        }
      }
    });

    exits.listen((_) {
      // Worker died (killed or crashed): fail what was waiting and respawn on the next call.
      _failAll(const CutePeripheralFailure('CUTE FFI worker exited'));
      if (!ready.isCompleted) {
        ready.completeError(const CutePeripheralFailure('CUTE FFI worker exited during start'));
      }
      _isolate = null;
      _sendPort = null;
      replies.close();
      exits.close();
      if (identical(_replies, replies)) _replies = null;
      if (identical(_exits, exits)) _exits = null;
    });

    try {
      _isolate = await Isolate.spawn<SendPort>(
        _workerMain,
        replies.sendPort,
        debugName: debugName,
        onExit: exits.sendPort,
        errorsAreFatal: false,
      );
    } catch (e) {
      replies.close();
      exits.close();
      _sendPort = null;
      throw CutePeripheralFailure('CUTE FFI worker could not start: $e');
    }
    if (_disposed) {
      _isolate?.kill(priority: Isolate.immediate);
      throw const CutePeripheralFailure('CUTE FFI worker is disposed');
    }
    return ready.future;
  }

  void _failAll(CutePeripheralFailure failure) {
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final completer in waiting) {
      if (!completer.isCompleted) completer.completeError(failure);
    }
  }
}

final class _Job<A, R> {
  const _Job(this.id, this.task, this.arg);

  final int id;
  final R Function(A arg) task;
  final A arg;

  Object? call() => task(arg);
}

final class _Reply {
  const _Reply(this.id, this.ok, this.value, [this.stack]);

  final int id;
  final bool ok;
  final Object? value;
  final String? stack;
}

void _workerMain(SendPort replies) {
  final jobs = ReceivePort();
  replies.send(jobs.sendPort);
  jobs.listen((Object? message) {
    if (message is! _Job) return;
    try {
      final value = message.call();
      try {
        replies.send(_Reply(message.id, true, value));
      } catch (e) {
        replies.send(
          _Reply(message.id, false, CutePeripheralFailure('CUTE FFI result could not be sent: $e')),
        );
      }
    } catch (error, stack) {
      try {
        replies.send(_Reply(message.id, false, error, stack.toString()));
      } catch (_) {
        replies.send(
          _Reply(message.id, false, CutePeripheralFailure(error.toString()), stack.toString()),
        );
      }
    }
  });
}
