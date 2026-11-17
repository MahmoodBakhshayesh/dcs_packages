import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../aea_helpers.dart';
import '../cute_ffi_worker.dart';
import '../cute_peripheral.dart';
import '../models.dart';
import 'resa_ffi.dart';

/// RESA CUTE peripheral via `crwnt_dm.dll`.
///
/// Every `CRW_DM_*` call runs on this device's [CuteFfiWorker] isolate: lock
/// and read wait in native code for up to their timeout and must not freeze
/// the UI isolate.
class ResaDevice implements CutePeripheral {
  ResaDevice({
    required this.identity,
    this.trace = false,
    this.defaultTimeoutMs = 300,
  }) : _worker = CuteFfiWorker(debugName: 'resa-${identity.name}');

  final CutePeripheralIdentity identity;
  final bool trace;
  final int defaultTimeoutMs;
  final CuteFfiWorker _worker;

  /// How long [close] / [dispose] wait for the worker before giving up on it.
  static const Duration closeTimeout = Duration(seconds: 5);

  @override
  CuteVendor get vendor => CuteVendor.resa;

  @override
  CutePeripheralKind get kind => identity.kind;

  @override
  String get displayName => identity.name;

  final _statusController = StreamController<CutePeripheralStatus>.broadcast();
  final _dataController = StreamController<List<int>>.broadcast();

  bool _open = false;
  CutePeripheralStatus _status = const CutePeripheralStatus(
    state: CutePeripheralState.disconnected,
    message: 'Disconnected',
  );

  @override
  Stream<CutePeripheralStatus> get statusChanges => _statusController.stream;

  @override
  CutePeripheralStatus get currentStatus => _status;

  @override
  Stream<List<int>> get data => _dataController.stream;

  String get _typeToken {
    // Prefer explicit name when it already looks like RESA token.
    final name = identity.name.trim().toUpperCase();
    if (name == 'RTE' || name == 'BPP' || name == 'BTP' || name == 'DCP' || name == 'BCD') {
      return name;
    }
    return switch (kind) {
      CutePeripheralKind.atb || CutePeripheralKind.bpp => 'BPP',
      CutePeripheralKind.btp => 'BTP',
      CutePeripheralKind.dcp => 'DCP',
      CutePeripheralKind.bcd => 'BCD',
      CutePeripheralKind.rte ||
      CutePeripheralKind.ocr ||
      CutePeripheralKind.msr ||
      CutePeripheralKind.lsr ||
      CutePeripheralKind.lsr2 =>
        'RTE',
      _ => 'BTP',
    };
  }

  @override
  Future<void> open() async {
    await _worker.run(_resaOpenTask, (_typeToken, identity.order, trace ? 1 : 0));
    _open = true;
    _setStatus(
      CutePeripheralStatus(
        state: CutePeripheralState.open,
        message: 'Opened $_typeToken#${identity.order}',
        online: true,
      ),
    );
  }

  @override
  Future<void> lock({Duration timeout = const Duration(seconds: 10)}) async {
    _requireOpen();
    await _worker.run(
      _resaLockTask,
      (_typeToken, identity.order, timeout.inMilliseconds.clamp(1, 60000)),
    );
    _setStatus(_status.copyWith(state: CutePeripheralState.locked, locked: true, message: 'Locked'));
  }

  @override
  Future<void> unlock() async {
    _requireOpen();
    await _worker.run(_resaUnlockTask, (_typeToken, identity.order));
    _setStatus(_status.copyWith(state: CutePeripheralState.open, locked: false, message: 'Unlocked'));
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> write(List<int> bytes, {bool endDoc = false}) async {
    _requireOpen();
    await _worker.run(
      _resaWriteTask,
      (_typeToken, identity.order, bytes, defaultTimeoutMs),
    );
  }

  @override
  Future<void> writeAea(
    String command, {
    bool endDoc = false,
    bool frame = true,
  }) async {
    await write(AeaHelpers.asciiBytes(command), endDoc: endDoc);
  }

  @override
  Future<List<int>?> read({Duration timeout = const Duration(seconds: 5)}) async {
    _requireOpen();
    final result = await _worker.run(
      _resaReadTask,
      (_typeToken, identity.order, timeout.inMilliseconds.clamp(1, 60000)),
    );
    if (result == null) return null;
    final (bytes, st) = result;
    if (!_dataController.isClosed) _dataController.add(bytes);
    _setStatus(_status.copyWith(rawCode: st, message: 'Read status $st'));
    return bytes;
  }

  @override
  Future<CutePeripheralStatus> queryStatus() async {
    await writeAea('QS');
    final reply = await read(timeout: const Duration(seconds: 2));
    if (reply == null) return _status;
    final text = AeaHelpers.decodeAscii(reply);
    final paperOk = AeaHelpers.paperOkFromSt(text);
    final next = _status.copyWith(
      online: true,
      paperOk: paperOk ?? _status.paperOk,
      message: text.isEmpty ? _status.message : text,
    );
    _setStatus(next);
    return next;
  }

  @override
  Future<void> close() async {
    final wasOpen = _open;
    _open = false;
    if (wasOpen && !_worker.isDisposed) {
      // Bounded: a worker stuck in a native wait must not hang close / dispose.
      try {
        await _worker.run(_resaCloseTask, (_typeToken, identity.order)).timeout(closeTimeout);
      } catch (_) {}
    }
    _setStatus(
      const CutePeripheralStatus(
        state: CutePeripheralState.disconnected,
        message: 'Disconnected',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await close();
    await _worker.dispose();
    await _statusController.close();
    await _dataController.close();
  }

  void _requireOpen() {
    if (!_open) {
      throw const CutePeripheralFailure('RESA device is not open');
    }
  }

  void _setStatus(CutePeripheralStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}

// ── Worker tasks ──────────────────────────────────────────────────────────────
// Top-level so they can be sent to the worker isolate. Each loads the bindings
// in the worker and owns its native memory.

void _resaOpenTask((String, int, int) args) {
  final (type, order, fTrace) = args;
  final api = ResaCrwBindings.load();
  final typePtr = type.toNativeUtf8();
  try {
    final rc = api.open(typePtr, order, fTrace);
    if (rc != ResaCrwBindings.crwOk) {
      throw CutePeripheralFailure('CRW_DM_OPEN failed', code: rc);
    }
  } finally {
    calloc.free(typePtr);
  }
}

void _resaLockTask((String, int, int) args) {
  final (type, order, timeoutMs) = args;
  final api = ResaCrwBindings.load();
  final typePtr = type.toNativeUtf8();
  try {
    final rc = api.lock(typePtr, order, timeoutMs);
    if (rc != ResaCrwBindings.crwOk) {
      throw CutePeripheralFailure('CRW_DM_LOCK failed', code: rc);
    }
  } finally {
    calloc.free(typePtr);
  }
}

void _resaUnlockTask((String, int) args) {
  final (type, order) = args;
  final api = ResaCrwBindings.load();
  final typePtr = type.toNativeUtf8();
  try {
    final rc = api.unlock(typePtr, order);
    if (rc != ResaCrwBindings.crwOk) {
      throw CutePeripheralFailure('CRW_DM_UNLOCK failed', code: rc);
    }
  } finally {
    calloc.free(typePtr);
  }
}

void _resaWriteTask((String, int, List<int>, int) args) {
  final (type, order, bytes, timeoutMs) = args;
  final api = ResaCrwBindings.load();
  final typePtr = type.toNativeUtf8();
  final msg = calloc<Uint8>(bytes.length);
  msg.asTypedList(bytes.length).setAll(0, bytes);
  try {
    final rc = api.write(typePtr, order, msg, bytes.length, ResaCrwBindings.aeaMode, timeoutMs);
    if (rc != ResaCrwBindings.crwOk) {
      throw CutePeripheralFailure('CRW_DM_WRITE failed', code: rc);
    }
  } finally {
    calloc.free(typePtr);
    calloc.free(msg);
  }
}

/// `CRW_DM_READ`; `null` when nothing arrived (error or empty), else the bytes
/// and the device status word.
(Uint8List, int)? _resaReadTask((String, int, int) args) {
  final (type, order, timeoutMs) = args;
  final api = ResaCrwBindings.load();
  final typePtr = type.toNativeUtf8();
  final msg = calloc<Uint8>(ResaCrwBindings.maxMsg);
  final status = calloc<Uint16>(2);
  final pcb = calloc<Uint16>(2);
  try {
    final rc = api.read(typePtr, order, msg, status, pcb, timeoutMs);
    if (rc != ResaCrwBindings.crwOk) return null;
    final len = pcb[0].clamp(0, ResaCrwBindings.maxMsg);
    if (len == 0) return null;
    return (Uint8List.fromList(msg.asTypedList(len)), status[0]);
  } finally {
    calloc.free(typePtr);
    calloc.free(msg);
    calloc.free(status);
    calloc.free(pcb);
  }
}

void _resaCloseTask((String, int) args) {
  final (type, order) = args;
  final api = ResaCrwBindings.load();
  final typePtr = type.toNativeUtf8();
  try {
    api.close(typePtr, order);
  } finally {
    calloc.free(typePtr);
  }
}
