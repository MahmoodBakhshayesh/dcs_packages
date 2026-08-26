import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../aea_helpers.dart';
import '../cute_peripheral.dart';
import '../models.dart';
import 'sita_ffi.dart';

/// SITA CUTE peripheral via `xspmapi.dll` (CUTE/NT SDK [kCuteNtSdkVersion]).
class SitaDevice implements CutePeripheral {
  SitaDevice({required this.identity});

  final CutePeripheralIdentity identity;

  @override
  CuteVendor get vendor => CuteVendor.sita;

  @override
  CutePeripheralKind get kind => identity.kind;

  @override
  String get displayName => identity.name;

  final _statusController = StreamController<CutePeripheralStatus>.broadcast();
  final _dataController = StreamController<List<int>>.broadcast();

  SitaXspmBindings? _api;
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
    final api = SitaXspmBindings.load();
    _api = api;
    final handlePtr = calloc<Uint32>();
    final namePtr = identity.name.trim().toNativeUtf8();
    final airlinePtr = _airlineId.toNativeUtf8();
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
      _handle = handlePtr.value;
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
    } finally {
      calloc.free(handlePtr);
      calloc.free(namePtr);
      calloc.free(airlinePtr);
    }
  }

  @override
  Future<void> lock({Duration timeout = const Duration(seconds: 10)}) async {
    final api = _requireApi();
    final handle = _requireHandle();
    final statusBuf = allocPmStatusBuffer();
    try {
      // HARD lock + hold reads; wait up to [timeout] seconds (WAITINDEFINITE = -1).
      final waitSecs = timeout.inSeconds <= 0
          ? SitaXspmBindings.waitIndefinite
          : timeout.inSeconds.clamp(1, 120);
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
      final bits = SitaDeviceStatusBits(statusBuf.ref.status);
      _setStatus(
        _statusFromBits(
          bits,
          state: CutePeripheralState.locked,
          message: 'Locked (${bits.summary})',
        ),
      );
    } finally {
      calloc.free(statusBuf);
    }
  }

  @override
  Future<void> unlock() async {
    // XSPMAPI.H has no XSPMUnlock. Official sample unlocks via Flush of lock requests
    // (and/or Close). Flush lock outstanding requests + RX data.
    final api = _requireApi();
    final handle = _requireHandle();
    final rc = api.flush(
      handle,
      SitaXspmBindings.pmFlushLock | SitaXspmBindings.pmFlushRxData,
      0,
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
    final api = _requireApi();
    final handle = _requireHandle();
    final rc = api.flush(handle, options, 0);
    if (rc != SitaXspmBindings.pmRetSuccess) {
      throw CutePeripheralFailure('XSPMFlush failed', code: rc);
    }
  }

  @override
  Future<void> write(List<int> bytes, {bool endDoc = false}) async {
    final api = _requireApi();
    final handle = _requireHandle();
    if (bytes.isEmpty) {
      if (endDoc || _isBgr) {
        await _writeChunk(api, handle, const <int>[], endDoc: true);
      }
      return;
    }

    // Chunk to MAX_MSGBUFFER_LEN (4000). Only the final chunk may set PM_ENDDOC.
    var offset = 0;
    while (offset < bytes.length) {
      final end = (offset + SitaXspmBindings.maxMsg).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);
      final isLast = end >= bytes.length;
      await _writeChunk(
        api,
        handle,
        chunk,
        endDoc: isLast && (endDoc || _isBgr),
      );
      offset = end;
    }
  }

  Future<void> _writeChunk(
    SitaXspmBindings api,
    int handle,
    List<int> chunk, {
    required bool endDoc,
  }) async {
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
    final api = _requireApi();
    final handle = _requireHandle();
    final deadline = DateTime.now().add(timeout);
    // Poll with PM_NOWAIT so the UI isolate is not blocked indefinitely.
    while (true) {
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
        if (rc == SitaXspmBindings.pmRetSuccess) {
          final bytes = copyPmDataMessage(buf);
          if (bytes.isEmpty) return null;
          if (!_dataController.isClosed) _dataController.add(bytes);
          return bytes;
        }
        if (rc != SitaXspmBindings.pmRetNrdy) {
          return null;
        }
      } finally {
        calloc.free(msg);
        calloc.free(buf);
      }
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  Future<CutePeripheralStatus> queryStatus() async {
    final api = _requireApi();
    final handle = _requireHandle();
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
      final bits = SitaDeviceStatusBits(statusBuf.ref.status);
      final next = _statusFromBits(
        bits,
        state: bits.lockOwned || bits.locked
            ? CutePeripheralState.locked
            : CutePeripheralState.open,
        message: bits.summary,
      );
      _setStatus(next);
      return next;
    } finally {
      calloc.free(statusBuf);
    }
  }

  @override
  Future<void> close() async {
    final api = _api;
    final handle = _handle;
    if (api != null && handle != null) {
      // Flush outstanding work then close (releases owned lock).
      try {
        api.flush(handle, SitaXspmBindings.pmFlushAll, 0);
      } catch (_) {}
      api.close(handle, 0);
    }
    _handle = null;
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

  SitaXspmBindings _requireApi() {
    final api = _api;
    if (api == null) throw const CutePeripheralFailure('SITA device is not open');
    return api;
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
