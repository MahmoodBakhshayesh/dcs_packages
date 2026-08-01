import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Native bindings for RESA `crwnt_dm.dll`.
class ResaCrwBindings {
  ResaCrwBindings._(DynamicLibrary lib)
      : _open = lib.lookupFunction<
            Uint16 Function(Pointer<Utf8>, Uint16, Uint16),
            int Function(Pointer<Utf8>, int, int)>('CRW_DM_OPEN'),
        _close = lib.lookupFunction<Uint16 Function(Pointer<Utf8>, Uint16), int Function(Pointer<Utf8>, int)>(
          'CRW_DM_CLOSE',
        ),
        _read = lib.lookupFunction<
            Uint16 Function(Pointer<Utf8>, Uint16, Pointer<Uint8>, Pointer<Uint16>, Pointer<Uint16>, Uint16),
            int Function(Pointer<Utf8>, int, Pointer<Uint8>, Pointer<Uint16>, Pointer<Uint16>, int)>('CRW_DM_READ'),
        _write = lib.lookupFunction<
            Uint16 Function(Pointer<Utf8>, Uint16, Pointer<Uint8>, Uint16, Uint16, Uint16),
            int Function(Pointer<Utf8>, int, Pointer<Uint8>, int, int, int)>('CRW_DM_WRITE'),
        _writeAsync = lib.lookupFunction<
            Uint16 Function(Pointer<Utf8>, Uint16, Pointer<Uint8>, Uint16, Uint16, Uint16),
            int Function(Pointer<Utf8>, int, Pointer<Uint8>, int, int, int)>('CRW_DM_WRITE_ASYNC'),
        _lock = lib.lookupFunction<Uint16 Function(Pointer<Utf8>, Uint16, Uint16), int Function(Pointer<Utf8>, int, int)>(
          'CRW_DM_LOCK',
        ),
        _unlock =
            lib.lookupFunction<Uint16 Function(Pointer<Utf8>, Uint16), int Function(Pointer<Utf8>, int)>('CRW_DM_UNLOCK');

  final int Function(Pointer<Utf8>, int, int) _open;
  final int Function(Pointer<Utf8>, int) _close;
  final int Function(Pointer<Utf8>, int, Pointer<Uint8>, Pointer<Uint16>, Pointer<Uint16>, int) _read;
  final int Function(Pointer<Utf8>, int, Pointer<Uint8>, int, int, int) _write;
  final int Function(Pointer<Utf8>, int, Pointer<Uint8>, int, int, int) _writeAsync;
  final int Function(Pointer<Utf8>, int, int) _lock;
  final int Function(Pointer<Utf8>, int) _unlock;

  static ResaCrwBindings? _instance;

  static ResaCrwBindings load() {
    if (!Platform.isWindows) {
      throw UnsupportedError('RESA crwnt_dm.dll is only available on Windows CUTE workstations.');
    }
    return _instance ??= ResaCrwBindings._(DynamicLibrary.open('crwnt_dm.dll'));
  }

  static const int crwOk = 0;
  static const int aeaMode = 1;
  static const int maxMsg = 32768;

  int open(Pointer<Utf8> type, int order, int fTrace) => _open(type, order, fTrace);
  int close(Pointer<Utf8> type, int order) => _close(type, order);
  int read(
    Pointer<Utf8> type,
    int order,
    Pointer<Uint8> msg,
    Pointer<Uint16> status,
    Pointer<Uint16> pcbMsg,
    int timeout,
  ) =>
      _read(type, order, msg, status, pcbMsg, timeout);
  int write(
    Pointer<Utf8> type,
    int order,
    Pointer<Uint8> msg,
    int count,
    int mode,
    int timeout,
  ) =>
      _write(type, order, msg, count, mode, timeout);
  int writeAsync(
    Pointer<Utf8> type,
    int order,
    Pointer<Uint8> msg,
    int count,
    int mode,
    int timeout,
  ) =>
      _writeAsync(type, order, msg, count, mode, timeout);
  int lock(Pointer<Utf8> type, int order, int timeout) => _lock(type, order, timeout);
  int unlock(Pointer<Utf8> type, int order) => _unlock(type, order);
}
