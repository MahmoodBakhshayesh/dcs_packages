import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../aea_helpers.dart';
import '../cute_peripheral.dart';
import '../models.dart';
import 'sita_ffi.dart';

/// SITA CUTE peripheral via `xspmapi.dll`.
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

  @override
  Future<void> open() async {
    final api = SitaXspmBindings.load();
    _api = api;
    final handlePtr = calloc<Uint32>();
    final namePtr = identity.name.toNativeUtf8();
    final airlinePtr = identity.airlineCode.toNativeUtf8();
    try {
      final rc = api.open(
        namePtr,
        handlePtr,
        SitaXspmBindings.pmWait,
        airlinePtr,
        -1,
        0,
      );
      if (rc != SitaXspmBindings.pmRetSuccess) {
        throw CutePeripheralFailure('XSPMOpen failed', code: rc);
      }
      _handle = handlePtr.value;
      _setStatus(
        CutePeripheralStatus(
          state: CutePeripheralState.open,
          message: 'Opened ${identity.name}',
          online: true,
        ),
      );
      if (_isPrinter) {
        await writeAea('SM;A08', frame: true);
      }
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
      final wait = timeout.inSeconds.clamp(1, 120);
      final rc = api.lock(
        handle,
        statusBuf,
        SitaXspmBindings.pmWait,
        0,
        wait,
        0,
      );
      if (rc != SitaXspmBindings.pmRetSuccess) {
        throw CutePeripheralFailure('XSPMLock failed', code: rc);
      }
      _setStatus(
        _status.copyWith(
          state: CutePeripheralState.locked,
          locked: true,
          rawCode: statusBuf.ref.status,
          message: 'Locked',
        ),
      );
    } finally {
      calloc.free(statusBuf);
    }
  }

  @override
  Future<void> unlock() async {
    // XPSM unlock is typically via Lock options / Close; flush pending ops.
    final api = _requireApi();
    final handle = _requireHandle();
    api.flush(handle, 0, 0);
    _setStatus(_status.copyWith(state: CutePeripheralState.open, locked: false, message: 'Unlocked'));
  }

  @override
  Future<void> write(List<int> bytes, {bool endDoc = false}) async {
    final api = _requireApi();
    final handle = _requireHandle();
    final payload = bytes.length > SitaXspmBindings.maxMsg
        ? bytes.sublist(0, SitaXspmBindings.maxMsg)
        : bytes;
    final buf = allocPmDataBuffer(payload);
    try {
      var option = SitaXspmBindings.pmWait;
      if (endDoc || _isBgr) option |= SitaXspmBindings.pmEndDoc;
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
    final msg = calloc<Uint8>(SitaXspmBindings.maxMsg);
    final buf = calloc<PmDataBuffer>();
    buf.ref.dbufLen = sizeOf<PmDataBuffer>();
    buf.ref.msgLen = SitaXspmBindings.maxMsg;
    buf.ref.msgBuff = msg;
    try {
      final rc = api.read(handle, buf, SitaXspmBindings.pmWait, 0, 0);
      if (rc != SitaXspmBindings.pmRetSuccess) {
        return null;
      }
      final len = buf.ref.msgLen.clamp(0, SitaXspmBindings.maxMsg);
      if (len == 0) return null;
      final bytes = Uint8List.fromList(msg.asTypedList(len));
      if (!_dataController.isClosed) _dataController.add(bytes);
      return bytes;
    } finally {
      calloc.free(msg);
      calloc.free(buf);
    }
  }

  @override
  Future<CutePeripheralStatus> queryStatus() async {
    final api = _requireApi();
    final handle = _requireHandle();
    final statusBuf = allocPmStatusBuffer();
    try {
      final rc = api.queryStatus(
        handle,
        statusBuf,
        SitaXspmBindings.pmNotifyChange,
        0,
        60,
        0,
      );
      if (rc != SitaXspmBindings.pmRetSuccess) {
        throw CutePeripheralFailure('XSPMQueryStatus failed', code: rc);
      }
      final next = _status.copyWith(
        online: true,
        rawCode: statusBuf.ref.status,
        message: 'Status ${statusBuf.ref.status}',
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
