import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../aea_helpers.dart';
import '../cute_ffi_worker.dart';
import '../cute_peripheral.dart';
import '../models.dart';
import 'sita_ffi.dart';

/// SITA CUTE peripheral via `xspmapi.dll` (CUTE/NT SDK [kCuteNtSdkVersion]).
///
/// Every `XSPM*` call runs on this device's [CuteFfiWorker] isolate: `PM_WAIT`
/// calls (open, lock, write) can block for seconds or indefinitely and must not
/// freeze the UI isolate.
class SitaDevice implements CutePeripheral {
  SitaDevice({required this.identity}) : _worker = CuteFfiWorker(debugName: 'sita-${identity.name}');

  final CutePeripheralIdentity identity;
  final CuteFfiWorker _worker;

  /// How long [close] / [dispose] wait for the worker before giving up on it.
  static const Duration closeTimeout = Duration(seconds: 5);

  @override
  CuteVendor get vendor => CuteVendor.sita;

  @override
  CutePeripheralKind get kind => identity.kind;

  @override
  String get displayName => identity.name;

  final _statusController = StreamController<CutePeripheralStatus>.broadcast();
  final _dataController = StreamController<List<int>>.broadcast();

  int? _handle;
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

  bool get _isPrinter => switch (kind) {
        CutePeripheralKind.atb ||
        CutePeripheralKind.btp ||
        CutePeripheralKind.bgr ||
        CutePeripheralKind.bgr2 ||
        CutePeripheralKind.bgr3 ||
        CutePeripheralKind.bgr4 ||
        CutePeripheralKind.bpp =>
          true,
        _ => false,
      };

  bool get _isBgr => switch (kind) {
        CutePeripheralKind.bgr ||
        CutePeripheralKind.bgr2 ||
        CutePeripheralKind.bgr3 ||
        CutePeripheralKind.bgr4 =>
          true,
        _ => false,
      };

  String get _airlineId {
    final code = identity.airlineCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw const CutePeripheralFailure(
        'SITA airline code is required for XSPMOpen (2–3 letter designator).',
      );
    }
    return code.length > 3 ? code.substring(0, 3) : code;
  }

  @override
  Future<void> open() async {
    final handle = await _worker.run(_sitaOpenTask, (identity.name.trim(), _airlineId));
    _handle = handle;
    _setStatus(
      CutePeripheralStatus(
        state: CutePeripheralState.open,
        message: 'Opened ${identity.name} (SDK $kCuteNtSdkVersion)',
        online: true,
      ),
    );
    if (_isPrinter) {
      // Standard ATB/BTP init — select stock / clear; ignore failure on non-AEA devices.
      try {
        await writeAea('SM;A08', frame: true);
      } catch (_) {}
    }
    await queryStatus();
  }

  @override
  Future<void> lock({Duration timeout = const Duration(seconds: 10)}) async {
    final handle = _requireHandle();
    // HARD lock + hold reads; wait up to [timeout] seconds (WAITINDEFINITE = -1).
    final waitSecs = timeout.inSeconds <= 0
        ? SitaXspmBindings.waitIndefinite
        : timeout.inSeconds.clamp(1, 120);
    final raw = await _worker.run(_sitaLockTask, (handle, waitSecs));
    final bits = SitaDeviceStatusBits(raw);
    _setStatus(
      _statusFromBits(
        bits,
        state: CutePeripheralState.locked,
        message: 'Locked (${bits.summary})',
      ),
    );
  }

  @override
  Future<void> unlock() async {
    // XSPMAPI.H has no XSPMUnlock. Official sample unlocks via Flush of lock requests
    // (and/or Close). Flush lock outstanding requests + RX data.
    final handle = _requireHandle();
    final rc = await _worker.run(
      _sitaFlushTask,
      (handle, SitaXspmBindings.pmFlushLock | SitaXspmBindings.pmFlushRxData),
    );
    if (rc != SitaXspmBindings.pmRetSuccess && rc != SitaXspmBindings.pmErrDevNotLocked) {
      throw CutePeripheralFailure('XSPMFlush(PM_FLUSHLOCK) failed', code: rc);
    }
    try {
      await queryStatus();
    } catch (_) {
      _setStatus(
        _status.copyWith(
          state: CutePeripheralState.open,
          locked: false,
          message: 'Unlocked',
        ),
      );
    }
  }

  /// Flush outstanding PM requests (`PM_FLUSH*` options from XSPMAPI.H).
  @override
  Future<void> flush({int options = SitaXspmBindings.pmFlushAll}) async {
    final handle = _requireHandle();
    final rc = await _worker.run(_sitaFlushTask, (handle, options));
    if (rc != SitaXspmBindings.pmRetSuccess) {
      throw CutePeripheralFailure('XSPMFlush failed', code: rc);
    }
  }

  @override
  Future<void> write(List<int> bytes, {bool endDoc = false}) async {
    final handle = _requireHandle();
    if (bytes.isEmpty) {
      if (endDoc || _isBgr) {
        await _worker.run(_sitaWriteChunkTask, (handle, const <int>[], true));
      }
      return;
    }

    // Chunk to MAX_MSGBUFFER_LEN (4000). Only the final chunk may set PM_ENDDOC.
    var offset = 0;
    while (offset < bytes.length) {
      final end = (offset + SitaXspmBindings.maxMsg).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);
      final isLast = end >= bytes.length;
      await _worker.run(
        _sitaWriteChunkTask,
        (handle, chunk, isLast && (endDoc || _isBgr)),
      );
      offset = end;
    }
  }

  @override
  Future<void> writeAea(
    String command, {
    bool endDoc = false,
    bool frame = true,
  }) async {
    final raw = AeaHelpers.asciiBytes(command);
    if (kind == CutePeripheralKind.dcp || !frame) {
      await write(raw, endDoc: endDoc);
      return;
    }
    final upper = command.trim().toUpperCase();
    final addAd = _isPrinter && !upper.startsWith('QS') && !upper.startsWith('SM');
    await write(AeaHelpers.frameSita(raw, addAdPrefix: addAd), endDoc: endDoc);
  }

  @override
  Future<List<int>?> read({Duration timeout = const Duration(seconds: 5)}) async {
    final handle = _requireHandle();
    final deadline = DateTime.now().add(timeout);
    // Poll with PM_NOWAIT so a quiet device never holds the worker.
    while (true) {
      final (rc, bytes) = await _worker.run(_sitaReadPollTask, handle);
      if (rc == SitaXspmBindings.pmRetSuccess) {
        if (bytes == null || bytes.isEmpty) return null;
        if (!_dataController.isClosed) _dataController.add(bytes);
        return bytes;
      }
      if (rc != SitaXspmBindings.pmRetNrdy) {
        return null;
      }
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  Future<CutePeripheralStatus> queryStatus() async {
    final handle = _requireHandle();
    final raw = await _worker.run(_sitaQueryStatusTask, handle);
    final bits = SitaDeviceStatusBits(raw);
    final next = _statusFromBits(
      bits,
      state: bits.lockOwned || bits.locked ? CutePeripheralState.locked : CutePeripheralState.open,
      message: bits.summary,
    );
    _setStatus(next);
    return next;
  }

  @override
  Future<void> close() async {
    final handle = _handle;
    _handle = null;
    if (handle != null && !_worker.isDisposed) {
      // Flush outstanding work then close (releases owned lock). Bounded: a worker
      // stuck in a native wait must not hang close / dispose.
      try {
        await _worker.run(_sitaCloseTask, handle).timeout(closeTimeout);
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

  CutePeripheralStatus _statusFromBits(
    SitaDeviceStatusBits bits, {
    required CutePeripheralState state,
    required String message,
  }) {
    return CutePeripheralStatus(
      state: state,
      message: message,
      online: bits.online,
      paperOk: bits.paperOk,
      locked: bits.locked || bits.lockOwned,
      rawCode: bits.raw,
    );
  }

  int _requireHandle() {
    final handle = _handle;
    if (handle == null) throw const CutePeripheralFailure('SITA device is not open');
    return handle;
  }

  void _setStatus(CutePeripheralStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}

// ── Worker tasks ──────────────────────────────────────────────────────────────
// Top-level so they can be sent to the worker isolate. Each loads the bindings
// in the worker and owns its native memory.

/// `XSPMOpen` with `PM_WAIT`; returns the PM handle.
int _sitaOpenTask((String, String) args) {
  final (name, airline) = args;
  final api = SitaXspmBindings.load();
  final handlePtr = calloc<Uint32>();
  final namePtr = name.toNativeUtf8();
  final airlinePtr = airline.toNativeUtf8();
  try {
    final rc = api.open(
      namePtr,
      handlePtr,
      SitaXspmBindings.pmWait,
      airlinePtr,
      SitaXspmBindings.defaultWaitTime,
      0,
    );
    if (rc != SitaXspmBindings.pmRetSuccess) {
      throw CutePeripheralFailure('XSPMOpen failed', code: rc);
    }
    return handlePtr.value;
  } finally {
    calloc.free(handlePtr);
    calloc.free(namePtr);
    calloc.free(airlinePtr);
  }
}

/// `XSPMLock` (hard lock, hold reads, `PM_WAIT`); returns the raw status bits.
int _sitaLockTask((int, int) args) {
  final (handle, waitSecs) = args;
  final api = SitaXspmBindings.load();
  final statusBuf = allocPmStatusBuffer();
  try {
    final rc = api.lock(
      handle,
      statusBuf,
      SitaXspmBindings.pmWait | SitaXspmBindings.pmHardLock | SitaXspmBindings.pmReadHold,
      0,
      waitSecs,
      0,
    );
    if (rc != SitaXspmBindings.pmRetSuccess) {
      throw CutePeripheralFailure('XSPMLock failed', code: rc);
    }
    return statusBuf.ref.status;
  } finally {
    calloc.free(statusBuf);
  }
}

/// `XSPMFlush`; returns the return code (the caller decides what is a failure).
int _sitaFlushTask((int, int) args) {
  final (handle, options) = args;
  return SitaXspmBindings.load().flush(handle, options, 0);
}

/// One `XSPMWrite` chunk (≤ `MAX_MSGBUFFER_LEN`) with `PM_WAIT`.
void _sitaWriteChunkTask((int, List<int>, bool) args) {
  final (handle, chunk, endDoc) = args;
  final api = SitaXspmBindings.load();
  final buf = allocPmDataBuffer(chunk);
  try {
    var option = SitaXspmBindings.pmWait;
    if (endDoc) option |= SitaXspmBindings.pmEndDoc;
    final rc = api.write(handle, buf, option, 0, 0);
    if (rc != SitaXspmBindings.pmRetSuccess) {
      throw CutePeripheralFailure('XSPMWrite failed', code: rc);
    }
  } finally {
    freePmDataBuffer(buf);
  }
}

/// One `XSPMRead` poll with `PM_NOWAIT`; returns the return code and, on
/// success, the message bytes.
(int, Uint8List?) _sitaReadPollTask(int handle) {
  final api = SitaXspmBindings.load();
  final msg = calloc<Uint8>(SitaXspmBindings.maxMsg);
  final buf = calloc<PmDataBuffer>();
  buf.ref.dbufLen = sizeOf<PmDataBuffer>();
  buf.ref.dbufLink = nullptr;
  buf.ref.dbufSem = nullptr;
  buf.ref.dbufFlags = 0;
  buf.ref.reserved = 0;
  buf.ref.userData = 0;
  buf.ref.userLink = 0;
  buf.ref.retCode = 0;
  buf.ref.status = 0;
  buf.ref.msgLen = SitaXspmBindings.maxMsg;
  buf.ref.msgBuff = msg;
  try {
    final rc = api.read(handle, buf, SitaXspmBindings.pmNoWait, 0, 0);
    if (rc != SitaXspmBindings.pmRetSuccess) return (rc, null);
    return (rc, copyPmDataMessage(buf));
  } finally {
    calloc.free(msg);
    calloc.free(buf);
  }
}

/// `XSPMQueryStatus` with `PM_NOTIFYIMMEDIATE`; returns the raw status bits.
int _sitaQueryStatusTask(int handle) {
  final api = SitaXspmBindings.load();
  final statusBuf = allocPmStatusBuffer();
  try {
    // PM_NOTIFYIMMEDIATE returns current status; PM_NOTIFYCHANGE waits for a change.
    final rc = api.queryStatus(
      handle,
      statusBuf,
      SitaXspmBindings.pmWait | SitaXspmBindings.pmNotifyImmediate,
      0,
      SitaXspmBindings.pmStatusMaskOps,
      0,
    );
    if (rc != SitaXspmBindings.pmRetSuccess && rc != SitaXspmBindings.pmRetNrdy) {
      throw CutePeripheralFailure('XSPMQueryStatus failed', code: rc);
    }
    return statusBuf.ref.status;
  } finally {
    calloc.free(statusBuf);
  }
}

/// `XSPMFlush(PM_FLUSHALL)` (errors ignored) then `XSPMClose`.
void _sitaCloseTask(int handle) {
  final api = SitaXspmBindings.load();
  try {
    api.flush(handle, SitaXspmBindings.pmFlushAll, 0);
  } catch (_) {}
  api.close(handle, 0);
}
