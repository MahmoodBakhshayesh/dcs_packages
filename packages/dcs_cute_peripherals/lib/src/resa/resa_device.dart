import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../aea_helpers.dart';
import '../cute_peripheral.dart';
import '../models.dart';
import 'resa_ffi.dart';

/// RESA CUTE peripheral via `crwnt_dm.dll`.
class ResaDevice implements CutePeripheral {
  ResaDevice({
    required this.identity,
    this.trace = false,
    this.defaultTimeoutMs = 300,
  });

  final CutePeripheralIdentity identity;
  final bool trace;
  final int defaultTimeoutMs;

  @override
  CuteVendor get vendor => CuteVendor.resa;

  @override
  CutePeripheralKind get kind => identity.kind;

  @override
  String get displayName => identity.name;

  final _statusController = StreamController<CutePeripheralStatus>.broadcast();
  final _dataController = StreamController<List<int>>.broadcast();

  ResaCrwBindings? _api;
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
    final api = ResaCrwBindings.load();
    _api = api;
    final typePtr = _typeToken.toNativeUtf8();
    try {
      final rc = api.open(typePtr, identity.order, trace ? 1 : 0);
      if (rc != ResaCrwBindings.crwOk) {
        throw CutePeripheralFailure('CRW_DM_OPEN failed', code: rc);
      }
      _open = true;
      _setStatus(
        CutePeripheralStatus(
          state: CutePeripheralState.open,
          message: 'Opened $_typeToken#${identity.order}',
          online: true,
        ),
      );
    } finally {
      calloc.free(typePtr);
    }
  }

  @override
  Future<void> lock({Duration timeout = const Duration(seconds: 10)}) async {
    final api = _requireApi();
    final typePtr = _typeToken.toNativeUtf8();
    try {
      final rc = api.lock(typePtr, identity.order, timeout.inMilliseconds.clamp(1, 60000));
      if (rc != ResaCrwBindings.crwOk) {
        throw CutePeripheralFailure('CRW_DM_LOCK failed', code: rc);
      }
      _setStatus(_status.copyWith(state: CutePeripheralState.locked, locked: true, message: 'Locked'));
    } finally {
      calloc.free(typePtr);
    }
  }

  @override
  Future<void> unlock() async {
    final api = _requireApi();
    final typePtr = _typeToken.toNativeUtf8();
    try {
      final rc = api.unlock(typePtr, identity.order);
      if (rc != ResaCrwBindings.crwOk) {
        throw CutePeripheralFailure('CRW_DM_UNLOCK failed', code: rc);
      }
      _setStatus(_status.copyWith(state: CutePeripheralState.open, locked: false, message: 'Unlocked'));
    } finally {
      calloc.free(typePtr);
    }
  }

  @override
  Future<void> write(List<int> bytes, {bool endDoc = false}) async {
    final api = _requireApi();
    final typePtr = _typeToken.toNativeUtf8();
    final msg = calloc<Uint8>(bytes.length);
    msg.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final rc = api.write(
        typePtr,
        identity.order,
        msg,
        bytes.length,
        ResaCrwBindings.aeaMode,
        defaultTimeoutMs,
      );
      if (rc != ResaCrwBindings.crwOk) {
        throw CutePeripheralFailure('CRW_DM_WRITE failed', code: rc);
      }
    } finally {
      calloc.free(typePtr);
      calloc.free(msg);
    }
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
    final api = _requireApi();
    final typePtr = _typeToken.toNativeUtf8();
    final msg = calloc<Uint8>(ResaCrwBindings.maxMsg);
    final status = calloc<Uint16>(2);
    final pcb = calloc<Uint16>(2);
    try {
      final rc = api.read(
        typePtr,
        identity.order,
        msg,
        status,
        pcb,
        timeout.inMilliseconds.clamp(1, 60000),
      );
      if (rc != ResaCrwBindings.crwOk) return null;
      final len = pcb[0].clamp(0, ResaCrwBindings.maxMsg);
      if (len == 0) return null;
      final bytes = Uint8List.fromList(msg.asTypedList(len));
      if (!_dataController.isClosed) _dataController.add(bytes);
      final st = status[0];
      _setStatus(_status.copyWith(rawCode: st, message: 'Read status $st'));
      return bytes;
    } finally {
      calloc.free(typePtr);
      calloc.free(msg);
      calloc.free(status);
      calloc.free(pcb);
    }
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
    final api = _api;
    if (api != null && _open) {
      final typePtr = _typeToken.toNativeUtf8();
      try {
        api.close(typePtr, identity.order);
      } finally {
        calloc.free(typePtr);
      }
    }
    _open = false;
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

  ResaCrwBindings _requireApi() {
    final api = _api;
    if (api == null || !_open) {
      throw const CutePeripheralFailure('RESA device is not open');
    }
    return api;
  }

  void _setStatus(CutePeripheralStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}
