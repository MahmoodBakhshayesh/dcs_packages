// Bindings derived from CUTE/NT SDK 1.34 `XSPMAPI.H`
// (CUTENTSDKSETUPINFOv11 / Sample Code TstPmApi).
//
// Important:
// - There is NO `XSPMUnlock` — release lock via `XSPMFlush(PM_FLUSHLOCK)` / close.
// - `PM_ENDDOC` and `PM_NOTIFYCHANGE` are both `0x0010` but apply to different
//   option parameters (WriteOption vs StatusOption) — that is correct per the header.
// - `PMHANDLE` is `ULONG` (32-bit). `HEV` is `HANDLE` (pointer-sized).
// - On 64-bit Windows, CUTE typically installs under WOW6432Node (32-bit DLL).
//   A 64-bit Flutter process cannot load a 32-bit `xspmapi.dll`.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// CUTE/NT Peripheral Manager API version this binding targets.
const String kCuteNtSdkVersion = '1.34';

/// Native bindings for SITA `xspmapi.dll` (Windows CUTE Peripheral Manager).
class SitaXspmBindings {
  SitaXspmBindings._(DynamicLibrary lib)
      : _open = lib.lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Uint32>, Uint32, Pointer<Utf8>, Int16, Uint32),
            int Function(Pointer<Utf8>, Pointer<Uint32>, int, Pointer<Utf8>, int, int)>('XSPMOpen'),
        _close = lib.lookupFunction<Int32 Function(Uint32, Uint32), int Function(int, int)>('XSPMClose'),
        _lock = lib.lookupFunction<
            Int32 Function(Uint32, Pointer<PmStatusBuffer>, Uint32, IntPtr, Int16, Uint32),
            int Function(int, Pointer<PmStatusBuffer>, int, int, int, int)>('XSPMLock'),
        _write = lib.lookupFunction<
            Int32 Function(Uint32, Pointer<PmDataBuffer>, Uint32, IntPtr, Uint32),
            int Function(int, Pointer<PmDataBuffer>, int, int, int)>('XSPMWrite'),
        _read = lib.lookupFunction<
            Int32 Function(Uint32, Pointer<PmDataBuffer>, Uint32, IntPtr, Uint32),
            int Function(int, Pointer<PmDataBuffer>, int, int, int)>('XSPMRead'),
        _queryStatus = lib.lookupFunction<
            Int32 Function(Uint32, Pointer<PmStatusBuffer>, Uint32, IntPtr, Uint32, Uint32),
            int Function(int, Pointer<PmStatusBuffer>, int, int, int, int)>('XSPMQueryStatus'),
        _flush = lib.lookupFunction<Int32 Function(Uint32, Uint32, Uint32), int Function(int, int, int)>('XSPMFlush'),
        _getConfiguredDevices = lib.lookupFunction<
            Int32 Function(Pointer<Uint16>, Pointer<PmDeviceInfo>, Uint16, Uint16, Uint32),
            int Function(Pointer<Uint16>, Pointer<PmDeviceInfo>, int, int, int)>('XSPMGetConfiguredDevices'),
        _getDeviceDescription = lib.lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<PmDeviceDesc>, Uint16, Uint16, Uint32),
            int Function(Pointer<Utf8>, Pointer<PmDeviceDesc>, int, int, int)>('XSPMGetDeviceDescription'),
        _getAltNodeName = lib.lookupFunction<
            Int32 Function(
                Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint16>, Pointer<Utf8>, Uint16, Uint32),
            int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint16>, Pointer<Utf8>, int, int)>(
              'XSPMGetAltNodeName'),
        _notifyApplicationState = lib.lookupFunction<
            Int32 Function(Pointer<Utf8>, Int32, Uint32),
            int Function(Pointer<Utf8>, int, int)>('XSPMNotifyApplicationState');

  final int Function(Pointer<Utf8>, Pointer<Uint32>, int, Pointer<Utf8>, int, int) _open;
  final int Function(int, int) _close;
  final int Function(int, Pointer<PmStatusBuffer>, int, int, int, int) _lock;
  final int Function(int, Pointer<PmDataBuffer>, int, int, int) _write;
  final int Function(int, Pointer<PmDataBuffer>, int, int, int) _read;
  final int Function(int, Pointer<PmStatusBuffer>, int, int, int, int) _queryStatus;
  final int Function(int, int, int) _flush;
  final int Function(Pointer<Uint16>, Pointer<PmDeviceInfo>, int, int, int) _getConfiguredDevices;
  final int Function(Pointer<Utf8>, Pointer<PmDeviceDesc>, int, int, int) _getDeviceDescription;
  final int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint16>, Pointer<Utf8>, int, int)
      _getAltNodeName;
  final int Function(Pointer<Utf8>, int, int) _notifyApplicationState;

  static SitaXspmBindings? _instance;

  static SitaXspmBindings load() {
    if (!Platform.isWindows) {
      throw UnsupportedError('SITA xspmapi.dll is only available on Windows CUTE workstations.');
    }
    return _instance ??= SitaXspmBindings._(DynamicLibrary.open('xspmapi.dll'));
  }

  // ── Wait / open ──────────────────────────────────────────────────────────
  static const int pmWait = 0x0000;
  static const int pmNoWait = 0x0001;
  static const int maxWaitTime = -2;
  static const int defaultWaitTime = -1;
  static const int waitIndefinite = -1;

  // ── StatusOption ─────────────────────────────────────────────────────────
  static const int pmNotifyImmediate = 0x0000;
  static const int pmNotifyChange = 0x0010;

  // ── WriteOption ──────────────────────────────────────────────────────────
  static const int pmEndDoc = 0x0010;
  static const int pmSearchTable = 0x0020;

  // ── LockOption ───────────────────────────────────────────────────────────
  static const int pmReadHold = 0x0000;
  static const int pmReadNoHold = 0x0010;
  static const int pmHardLock = 0x0000;
  static const int pmSoftLock = 0x0100;
  static const int pmNoEject = 0x0200;
  static const int pmEject = 0x0000;

  // ── FlushOption ──────────────────────────────────────────────────────────
  static const int pmFlushRead = 0x0100;
  static const int pmFlushWrite = 0x0200;
  static const int pmFlushStatus = 0x0400;
  static const int pmFlushLock = 0x0800;
  static const int pmFlushRxData = 0x1000;
  static const int pmFlushAll = 0x1F00;

  // ── Device status bits (PMDSTAT_*) ───────────────────────────────────────
  static const int pmDstatRPend = 0x0001;
  static const int pmDstatWPend = 0x0002;
  static const int pmDstatSPend = 0x0004;
  static const int pmDstatLPend = 0x0008;
  static const int pmDstatOnline = 0x0010;
  static const int pmDstatNoPaper = 0x0020;
  static const int pmDstatInDataRdy = 0x0100;
  static const int pmDstatOutDataPend = 0x0200;
  static const int pmDstatLocked = 0x0400;
  static const int pmDstatLockOwned = 0x0800;
  static const int pmDstatCts = 0x1000;
  static const int pmDstatDsr = 0x2000;
  static const int pmDstatDcd = 0x4000;
  static const int pmDstatPoll = 0x8000;
  static const int pmDstatGoAhead = 0x10000;
  static const int pmDstatZ1Navbl = 0x20000;
  static const int pmDstatZ2Navbl = 0x40000;
  static const int pmDstatResaNavbl = 0x80000;
  static const int pmDstatRnr = 0x100000;
  static const int pmDstatMediaPresent = 0x200000;
  static const int pmDstatMediaSeated = 0x400000;
  static const int pmDstatMediaLatched = 0x800000;

  /// Useful mask for ops UI: online / paper / lock / inbound data.
  static const int pmStatusMaskOps = pmDstatOnline |
      pmDstatNoPaper |
      pmDstatInDataRdy |
      pmDstatLocked |
      pmDstatLockOwned;

  // ── Return codes ─────────────────────────────────────────────────────────
  static const int pmRetSuccess = 0;
  static const int pmRetNrdy = -1;
  static const int pmErrNoPm = -100;
  static const int pmErrNoRemotePm = -101;
  static const int pmErrIpcFailed = -102;
  static const int pmErrInvalidHandle = -110;
  static const int pmErrInvalidSBuffer = -111;
  static const int pmErrInvalidDBuffer = -112;
  static const int pmErrInvalidOption = -113;
  static const int pmErrDevFlushed = -115;
  static const int pmErrDevClosed = -116;
  static const int pmErrInvalidDevice = -120;
  static const int pmErrInvalidAirId = -121;
  static const int pmErrNoInstances = -122;
  static const int pmErrNoMoreHandles = -123;
  static const int pmErrUnsupportedMask = -124;
  static const int pmErrDevLocked = -128;
  static const int pmErrDevNotLocked = -129;
  static const int pmErrDevLockOwned = -130;
  static const int pmErrMsgTooLong = -132;
  static const int pmErrMoreData = -134;

  /// Max bytes per Write/Read message buffer (`MAX_MSGBUFFER_LEN`).
  static const int maxMsg = 4000;

  static const int getConfiguredDevicesVer = 0;
  static const int getDeviceDescVer = 0;
  static const int getAltNodeVer = 0;

  // ── Device types (`Devtypes.h`) ──────────────────────────────────────────
  static const int atbType = 10;
  static const int btpType = 11;
  static const int bgrType = 12;
  static const int bcrType = 13;
  static const int msrBase = 20;
  static const int msrType = 21;
  static const int ocrType = 22;
  static const int lsrType = 23;
  static const int dipType = 24;
  static const int ptrType = 40;
  static const int dcpType = 50;
  static const int gwyType = 90;

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

  int getConfiguredDevices(
    Pointer<Uint16> devNum,
    Pointer<PmDeviceInfo> devInfoArray,
    int devInfoArraySize,
    int version,
    int reserved,
  ) =>
      _getConfiguredDevices(devNum, devInfoArray, devInfoArraySize, version, reserved);

  int getDeviceDescription(
    Pointer<Utf8> devName,
    Pointer<PmDeviceDesc> desc,
    int descSize,
    int version,
    int reserved,
  ) =>
      _getDeviceDescription(devName, desc, descSize, version, reserved);

  int getAltNodeName(
    Pointer<Utf8> airlineName,
    Pointer<Utf8> clientWksName,
    Pointer<Uint16> altNodeLength,
    Pointer<Utf8> altNodeStr,
    int version,
    int reserved,
  ) =>
      _getAltNodeName(airlineName, clientWksName, altNodeLength, altNodeStr, version, reserved);

  /// `Active` is Win32 `BOOL` (32-bit): non-zero = active.
  int notifyApplicationState(Pointer<Utf8> airlineName, int active, int reserved) =>
      _notifyApplicationState(airlineName, active, reserved);
}

/// `GWYSTATUS` — 8 bytes under MSVC default alignment (ULONG + UCHAR + pad).
final class GwyStatusEntry extends Struct {
  @Uint32()
  external int status;
  @Uint8()
  external int devId;
  /// MSVC pads [GWYSTATUS] to 8 bytes (layout only).
  @Array(3)
  external Array<Uint8> pad; // ignore: unused_field
}

/// `PMSTATUSBUFFER` including trailing `GwyStatus[16]` (required for correct sizeof).
final class PmStatusBuffer extends Struct {
  @Uint32()
  external int sbufLen;
  external Pointer<Void> sbufLink;
  /// `HEV` / `HANDLE` — pointer-sized.
  external Pointer<Void> sbufSem;
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
  @Array(16)
  external Array<GwyStatusEntry> gwyStatus;
}

/// `PMDATABUFFER`
final class PmDataBuffer extends Struct {
  @Uint32()
  external int dbufLen;
  external Pointer<Void> dbufLink;
  external Pointer<Void> dbufSem;
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

/// `PMDEVICEINFO` — name is 6 bytes (not necessarily NUL-terminated).
final class PmDeviceInfo extends Struct {
  @Array(6)
  external Array<Uint8> pmDeviceName;
  @Uint16()
  external int pmDeviceType;
  @Array(11)
  external Array<Uint8> location;
}

/// `PMDEVICEDESC`
final class PmDeviceDesc extends Struct {
  @Array(10)
  external Array<Uint8> manufacturer;
  @Array(10)
  external Array<Uint8> printerType;
  @Array(10)
  external Array<Uint8> firmware;
  @Array(10)
  external Array<Uint8> serialNum;
}

Pointer<PmDataBuffer> allocPmDataBuffer(List<int> bytes) {
  final len = bytes.length.clamp(0, SitaXspmBindings.maxMsg);
  final msg = calloc<Uint8>(len == 0 ? 1 : len);
  if (len > 0) {
    msg.asTypedList(len).setAll(0, bytes.sublist(0, len));
  }
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
  buf.ref.msgLen = len;
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
  buf.ref.sbufLink = nullptr;
  buf.ref.sbufSem = nullptr;
  buf.ref.sbufFlags = 0;
  buf.ref.reserved = 0;
  buf.ref.userData = 0;
  buf.ref.userLink = 0;
  buf.ref.retCode = 0;
  buf.ref.status = 0;
  return buf;
}

String _fixedCString(Array<Uint8> bytes, int length) {
  final list = <int>[];
  for (var i = 0; i < length; i++) {
    final b = bytes[i];
    if (b == 0) break;
    list.add(b);
  }
  return String.fromCharCodes(list).trim();
}

class SitaConfiguredDevice {
  const SitaConfiguredDevice({
    required this.name,
    required this.deviceType,
    required this.location,
  });

  final String name;
  final int deviceType;
  final String location;
}

class SitaDeviceDescription {
  const SitaDeviceDescription({
    required this.manufacturer,
    required this.printerType,
    required this.firmware,
    required this.serialNum,
  });

  final String manufacturer;
  final String printerType;
  final String firmware;
  final String serialNum;
}

/// Decodes `PMDSTAT_*` bits into human-readable flags.
class SitaDeviceStatusBits {
  const SitaDeviceStatusBits(this.raw);

  final int raw;

  bool get online => (raw & SitaXspmBindings.pmDstatOnline) != 0;
  bool get noPaper => (raw & SitaXspmBindings.pmDstatNoPaper) != 0;
  bool get paperOk => !noPaper;
  bool get locked => (raw & SitaXspmBindings.pmDstatLocked) != 0;
  bool get lockOwned => (raw & SitaXspmBindings.pmDstatLockOwned) != 0;
  bool get inputDataReady => (raw & SitaXspmBindings.pmDstatInDataRdy) != 0;
  bool get outDataPending => (raw & SitaXspmBindings.pmDstatOutDataPend) != 0;

  String get summary {
    final parts = <String>[
      if (online) 'online' else 'offline',
      if (noPaper) 'no-paper',
      if (locked) 'locked',
      if (lockOwned) 'lock-owned',
      if (inputDataReady) 'data-ready',
      if (outDataPending) 'out-pending',
    ];
    return parts.isEmpty ? 'status=0x${raw.toRadixString(16)}' : parts.join(', ');
  }
}

/// Enumerate configured PM devices (two-step call per XSPMAPI.H).
///
/// [airlineCode] packs up to 3 airline chars into the VPS `Reserved` ULONG
/// when non-empty (see XSPMAPI.H note on VPS support).
List<SitaConfiguredDevice> sitaGetConfiguredDevices({String? airlineCode}) {
  final api = SitaXspmBindings.load();
  final countPtr = calloc<Uint16>();
  final reserved = _packAirlineReserved(airlineCode);
  try {
    // Step 1: query count with null array.
    var rc = api.getConfiguredDevices(
      countPtr,
      nullptr,
      0,
      SitaXspmBindings.getConfiguredDevicesVer,
      reserved,
    );
    if (rc != SitaXspmBindings.pmRetSuccess) {
      throw Exception('XSPMGetConfiguredDevices (count) failed: $rc');
    }
    final count = countPtr.value;
    if (count <= 0) return const [];

    final array = calloc<PmDeviceInfo>(count);
    try {
      rc = api.getConfiguredDevices(
        countPtr,
        array,
        sizeOf<PmDeviceInfo>() * count,
        SitaXspmBindings.getConfiguredDevicesVer,
        reserved,
      );
      if (rc != SitaXspmBindings.pmRetSuccess) {
        throw Exception('XSPMGetConfiguredDevices (fill) failed: $rc');
      }
      final n = countPtr.value.clamp(0, count).toInt();
      return [
        for (var i = 0; i < n; i++)
          SitaConfiguredDevice(
            name: _fixedCString(array[i].pmDeviceName, 6),
            deviceType: array[i].pmDeviceType,
            location: _fixedCString(array[i].location, 11),
          ),
      ];
    } finally {
      calloc.free(array);
    }
  } finally {
    calloc.free(countPtr);
  }
}

/// Packs up to 3 airline designator bytes into a ULONG (little-endian).
int _packAirlineReserved(String? airlineCode) {
  final code = airlineCode?.trim().toUpperCase() ?? '';
  if (code.isEmpty) return 0;
  var value = 0;
  final n = code.length < 3 ? code.length : 3;
  for (var i = 0; i < n; i++) {
    value |= (code.codeUnitAt(i) & 0xff) << (8 * i);
  }
  return value;
}

/// Notify Peripheral Manager that the application is active/inactive.
void sitaNotifyApplicationState({
  required String airlineCode,
  required bool active,
}) {
  final api = SitaXspmBindings.load();
  final airlinePtr = airlineCode.trim().toUpperCase().toNativeUtf8();
  try {
    final rc = api.notifyApplicationState(airlinePtr, active ? 1 : 0, 0);
    if (rc != SitaXspmBindings.pmRetSuccess) {
      throw Exception('XSPMNotifyApplicationState failed: $rc');
    }
  } finally {
    calloc.free(airlinePtr);
  }
}

SitaDeviceDescription? sitaGetDeviceDescription(String deviceName) {
  final api = SitaXspmBindings.load();
  final namePtr = deviceName.toNativeUtf8();
  final desc = calloc<PmDeviceDesc>();
  try {
    final rc = api.getDeviceDescription(
      namePtr,
      desc,
      sizeOf<PmDeviceDesc>(),
      SitaXspmBindings.getDeviceDescVer,
      0,
    );
    if (rc == SitaXspmBindings.pmErrInvalidOption) {
      // Device does not support description API.
      return null;
    }
    if (rc != SitaXspmBindings.pmRetSuccess) {
      throw Exception('XSPMGetDeviceDescription failed: $rc');
    }
    return SitaDeviceDescription(
      manufacturer: _fixedCString(desc.ref.manufacturer, 10),
      printerType: _fixedCString(desc.ref.printerType, 10),
      firmware: _fixedCString(desc.ref.firmware, 10),
      serialNum: _fixedCString(desc.ref.serialNum, 10),
    );
  } finally {
    calloc.free(namePtr);
    calloc.free(desc);
  }
}

Uint8List copyPmDataMessage(Pointer<PmDataBuffer> buf) {
  final len = buf.ref.msgLen.clamp(0, SitaXspmBindings.maxMsg);
  if (len == 0 || buf.ref.msgBuff == nullptr) return Uint8List(0);
  return Uint8List.fromList(buf.ref.msgBuff.asTypedList(len));
}
