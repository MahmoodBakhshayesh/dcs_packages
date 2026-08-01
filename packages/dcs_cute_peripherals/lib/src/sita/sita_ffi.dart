import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Native bindings for SITA `xspmapi.dll` (Windows CUTE Peripheral Manager).
class SitaXspmBindings {
  SitaXspmBindings._(DynamicLibrary lib)
      : _open = lib.lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Uint32>, Uint32, Pointer<Utf8>, Int16, Uint32),
            int Function(Pointer<Utf8>, Pointer<Uint32>, int, Pointer<Utf8>, int, int)>('XSPMOpen'),
        _close = lib.lookupFunction<Int32 Function(Uint32, Uint32), int Function(int, int)>('XSPMClose'),
        _lock = lib.lookupFunction<
            Int32 Function(Uint32, Pointer<PmStatusBuffer>, Uint32, Uint32, Int16, Uint32),
            int Function(int, Pointer<PmStatusBuffer>, int, int, int, int)>('XSPMLock'),
        _write = lib.lookupFunction<
            Int32 Function(Uint32, Pointer<PmDataBuffer>, Uint32, Uint32, Uint32),
            int Function(int, Pointer<PmDataBuffer>, int, int, int)>('XSPMWrite'),
        _read = lib.lookupFunction<
            Int32 Function(Uint32, Pointer<PmDataBuffer>, Uint32, Uint32, Uint32),
            int Function(int, Pointer<PmDataBuffer>, int, int, int)>('XSPMRead'),
        _queryStatus = lib.lookupFunction<
            Int32 Function(Uint32, Pointer<PmStatusBuffer>, Uint32, Uint32, Uint32, Uint32),
            int Function(int, Pointer<PmStatusBuffer>, int, int, int, int)>('XSPMQueryStatus'),
        _flush = lib.lookupFunction<Int32 Function(Uint32, Uint32, Uint32), int Function(int, int, int)>('XSPMFlush');

  final int Function(Pointer<Utf8>, Pointer<Uint32>, int, Pointer<Utf8>, int, int) _open;
  final int Function(int, int) _close;
  final int Function(int, Pointer<PmStatusBuffer>, int, int, int, int) _lock;
  final int Function(int, Pointer<PmDataBuffer>, int, int, int) _write;
  final int Function(int, Pointer<PmDataBuffer>, int, int, int) _read;
  final int Function(int, Pointer<PmStatusBuffer>, int, int, int, int) _queryStatus;
  final int Function(int, int, int) _flush;

  static SitaXspmBindings? _instance;

  static SitaXspmBindings load() {
    if (!Platform.isWindows) {
      throw UnsupportedError('SITA xspmapi.dll is only available on Windows CUTE workstations.');
    }
    return _instance ??= SitaXspmBindings._(DynamicLibrary.open('xspmapi.dll'));
  }

  static const int pmWait = 0;
  static const int pmEndDoc = 0x0010;
  static const int pmNotifyChange = 0x0010;
  static const int pmRetSuccess = 0;
  static const int maxMsg = 4000;

  int open(
    Pointer<Utf8> deviceName,
    Pointer<Uint32> handle,
    int openOption,
    Pointer<Utf8> airlineId,
    int dataWaitTime,
    int reserved,
  ) =>
      _open(deviceName, handle, openOption, airlineId, dataWaitTime, reserved);

  int close(int handle, int reserved) => _close(handle, reserved);

  int lock(
    int handle,
    Pointer<PmStatusBuffer> statusBuf,
    int lockOption,
    int semaphore,
    int getLockWaitTime,
    int reserved,
  ) =>
      _lock(handle, statusBuf, lockOption, semaphore, getLockWaitTime, reserved);

  int write(
    int handle,
    Pointer<PmDataBuffer> dataBuf,
    int writeOption,
    int semaphore,
    int reserved,
  ) =>
      _write(handle, dataBuf, writeOption, semaphore, reserved);

  int read(
    int handle,
    Pointer<PmDataBuffer> dataBuf,
    int readOption,
    int semaphore,
    int reserved,
  ) =>
      _read(handle, dataBuf, readOption, semaphore, reserved);

  int queryStatus(
    int handle,
    Pointer<PmStatusBuffer> statusBuf,
    int statusOption,
    int semaphore,
    int mask,
    int reserved,
  ) =>
      _queryStatus(handle, statusBuf, statusOption, semaphore, mask, reserved);

  int flush(int handle, int flushOption, int reserved) => _flush(handle, flushOption, reserved);
}

final class PmStatusBuffer extends Struct {
  @Uint32()
  external int sbufLen;
  external Pointer<Void> sbufLink;
  @Uint32()
  external int sbufSem;
  @Uint32()
  external int sbufFlags;
  @Uint32()
  external int reserved;
  @Uint32()
  external int userData;
  @Uint32()
  external int userLink;
  @Int32()
  external int retCode;
  @Uint32()
  external int status;
}

final class PmDataBuffer extends Struct {
  @Uint32()
  external int dbufLen;
  external Pointer<Void> dbufLink;
  @Uint32()
  external int dbufSem;
  @Uint32()
  external int dbufFlags;
  @Uint32()
  external int reserved;
  @Uint32()
  external int userData;
  @Uint32()
  external int userLink;
  @Int32()
  external int retCode;
  @Uint32()
  external int status;
  @Uint32()
  external int msgLen;
  external Pointer<Uint8> msgBuff;
}

Pointer<PmDataBuffer> allocPmDataBuffer(List<int> bytes) {
  final msg = calloc<Uint8>(bytes.length);
  msg.asTypedList(bytes.length).setAll(0, bytes);
  final buf = calloc<PmDataBuffer>();
  buf.ref.dbufLen = sizeOf<PmDataBuffer>();
  buf.ref.msgLen = bytes.length;
  buf.ref.msgBuff = msg;
  return buf;
}

void freePmDataBuffer(Pointer<PmDataBuffer> buf) {
  if (buf.ref.msgBuff != nullptr) {
    calloc.free(buf.ref.msgBuff);
  }
  calloc.free(buf);
}

Pointer<PmStatusBuffer> allocPmStatusBuffer() {
  final buf = calloc<PmStatusBuffer>();
  buf.ref.sbufLen = sizeOf<PmStatusBuffer>();
  return buf;
}
