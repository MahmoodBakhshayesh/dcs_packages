// Native (`dart:ffi`) serial adapter. `dcs_adapters.dart` exports this file only where `dart:ffi`
// exists; web gets `dcs_serial_port_adapter_stub.dart` instead, because libserialport is an FFI binding.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'dcs_adapters.dart';
import 'dcs_models.dart';

/// Desktop serial adapter backed by flutter_libserialport.
class DcsSerialPortAdapter implements DcsDeviceAdapter {
  const DcsSerialPortAdapter();

  @override
  DcsDeviceTransport get transport => DcsDeviceTransport.serial;

  @override
  Future<List<DcsDiscoveredDevice>> discover() async {
    return SerialPort.availablePorts
        .map(_deviceFromPortName)
        .toList(growable: false);
  }

  @override
  Future<DcsDeviceSession> connect(
    DcsDeviceProfile profile,
    DcsDiscoveredDevice device,
  ) async {
    if (profile.connectionType == DcsConnectionType.lan) {
      throw const DcsDeviceConnectionException(
        'Serial adapter cannot open LAN profiles. Use the network adapter.',
      );
    }
    if (profile.connectionType == DcsConnectionType.lpt) {
      throw const DcsDeviceConnectionException(
        'Serial adapter cannot open LPT profiles. Use the LPT adapter.',
      );
    }

    final port = SerialPort(device.portName);
    final options = profile.serialOptions;
    final config = SerialPortConfig()
      ..baudRate = options.baudRate
      ..bits = options.dataBits
      ..stopBits = options.stopBits
      ..parity = options.parity
      ..dtr = options.dtrEnable ? SerialPortDtr.on : SerialPortDtr.off
      ..rts = options.rtsEnable ? SerialPortRts.on : SerialPortRts.off
      ..setFlowControl(_flowControlValue(options.flowControl));

    port.config = config;

    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      final code = error?.errorCode;
      final message = error?.message ?? 'unknown serial error';
      final denied = code == 5 ||
          message.toLowerCase().contains('access is denied') ||
          message.toLowerCase().contains('access denied');
      throw DcsDeviceConnectionException(
        denied
            ? 'Could not open serial port ${device.portName}: Access denied. '
                'Another app (or CUPPS) may be using this COM port — close it and reconnect.'
            : 'Could not open serial port ${device.portName}: $message',
        code: code,
      );
    }

    return _DcsSerialPortSession(
      port,
      writeTimeout: options.writeTimeout,
      rtsEnable: options.rtsEnable,
    );
  }

  static DcsDiscoveredDevice _deviceFromPortName(String portName) {
    final port = SerialPort(portName);
    try {
      final description = _blankToNull(port.description);
      final transport = _blankToNull(port.transport.toString());
      final metadata = <String, String>{};
      if (description != null) {
        metadata['description'] = description;
      }
      if (transport != null) {
        metadata['transport'] = transport;
      }

      return DcsDiscoveredDevice(
        id: 'serial:$portName',
        portName: portName,
        transport: DcsDeviceTransport.serial,
        manufacturer: _blankToNull(port.manufacturer),
        productName: _blankToNull(port.productName),
        serialNumber: _blankToNull(port.serialNumber),
        vendorId: port.vendorId,
        productId: port.productId,
        metadata: metadata,
      );
    } finally {
      port.dispose();
    }
  }
}

class _DcsSerialPortSession implements DcsDeviceSession {
  _DcsSerialPortSession(
    this._port, {
    this.writeTimeout = const Duration(milliseconds: 8000),
    this.rtsEnable = true,
  }) {
    _reader = SerialPortReader(_port);
    _dataSubscription = _reader.stream.listen(
      _dataController.add,
      onError: _dataController.addError,
      onDone: _dataController.close,
    );
  }

  final SerialPort _port;
  final Duration writeTimeout;
  final bool rtsEnable;
  final StreamController<List<int>> _dataController =
      StreamController.broadcast();
  late final SerialPortReader _reader;
  late final StreamSubscription<Uint8List> _dataSubscription;
  var _closed = false;

  @override
  Stream<List<int>> get data => _dataController.stream;

  @override
  bool get isOpen => !_closed && _port.isOpen;

  @override
  Future<void> write(List<int> bytes) async {
    if (!isOpen) {
      throw const DcsDeviceConnectionException('Serial port is closed.');
    }
    _ensurePortStillPresent();
    if (bytes.isEmpty) return;

    // Match standalone C# SerialPortBase.Send: assert RTS before every write.
    if (rtsEnable) {
      try {
        final cfg = _port.config;
        cfg.rts = SerialPortRts.on;
        _port.config = cfg;
      } catch (_) {}
    }

    // Default libserialport write is non-blocking and often returns a partial
    // count for large AEA payloads (CP#). Loop with a real timeout so the full
    // document leaves the TX buffer (or we fail cleanly).
    final data = Uint8List.fromList(bytes);
    var offset = 0;
    final deadline = DateTime.now().add(writeTimeout);

    while (offset < data.length) {
      if (!_port.isOpen) {
        _markDead();
        throw DcsDeviceConnectionException(
          'Serial port ${_port.name} closed during write '
          '(offset $offset of ${data.length}).',
        );
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw DcsDeviceConnectionException(
          'Serial write timed out after $offset of ${data.length} bytes '
          '(${_port.name}).',
        );
      }

      final chunk = Uint8List.sublistView(data, offset);
      final timeoutMs = remaining.inMilliseconds.clamp(1, 60000);
      // timeout >= 0 => blocking write up to timeoutMs.
      late final int written;
      try {
        written = _port.write(chunk, timeout: timeoutMs);
      } catch (error) {
        _markDead();
        throw DcsDeviceConnectionException(
          'Serial write failed on ${_port.name}: $error',
        );
      }
      if (written < 0) {
        final error = SerialPort.lastError;
        _markDead();
        throw DcsDeviceConnectionException(
          'Serial write failed on ${_port.name}: '
          '${error?.message ?? 'unknown serial error'}',
          code: error?.errorCode,
        );
      }
      if (written == 0) {
        // Yield so timers / UI can run, then retry until deadline.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        continue;
      }
      offset += written;
    }
  }

  @override
  Future<void> ping() async {
    if (!isOpen) {
      throw const DcsDeviceConnectionException('Serial port is not open.');
    }
    _ensurePortStillPresent();
    // Touch the handle — when the printer is powered off Windows may keep
    // isOpen=true until I/O; bytesAvailable / config often fail sooner.
    try {
      // ignore: unnecessary_statements
      _port.bytesAvailable;
      final _ = _port.config;
    } catch (error) {
      _markDead();
      throw DcsDeviceConnectionException(
        'Serial port ${_port.name} is no longer healthy: $error',
      );
    }
  }

  void _ensurePortStillPresent() {
    final name = _port.name?.trim() ?? '';
    if (name.isEmpty) return;
    final available = SerialPort.availablePorts;
    final present = available.any((p) => p.trim().toUpperCase() == name.toUpperCase());
    if (!present) {
      _markDead();
      throw DcsDeviceConnectionException(
        'Serial port $name is no longer available (device unplugged or powered off).',
      );
    }
  }

  /// Marks the session dead. Does **not** release the OS handle — call [close].
  ///
  /// Previously error paths set `_closed = true` and [close] then returned early
  /// without `port.close()` / `dispose()`, so Windows kept ERROR_ACCESS_DENIED (5)
  /// on the next CreateFile after a power cycle.
  void _markDead() {
    _closed = true;
  }

  var _released = false;

  /// Always release the COM handle, even if a prior ping/write already marked
  /// the session dead. Idempotent.
  @override
  Future<void> close() async {
    _closed = true;
    if (_released) return;
    _released = true;
    try {
      await _dataSubscription.cancel();
    } catch (_) {}
    try {
      _reader.close();
    } catch (_) {}
    try {
      if (_port.isOpen) {
        _port.close();
      }
    } catch (_) {}
    try {
      _port.dispose();
    } catch (_) {}
    if (!_dataController.isClosed) {
      await _dataController.close();
    }
  }
}

String? _blankToNull(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value;
}

int _flowControlValue(DcsSerialFlowControl flowControl) {
  return switch (flowControl) {
    DcsSerialFlowControl.none => SerialPortFlowControl.none,
    DcsSerialFlowControl.xonXoff => SerialPortFlowControl.xonXoff,
    DcsSerialFlowControl.rtsCts ||
    DcsSerialFlowControl.requestToSend =>
      SerialPortFlowControl.rtsCts,
    DcsSerialFlowControl.dtrDsr => SerialPortFlowControl.dtrDsr,
    DcsSerialFlowControl.requestToSendXonXoff => SerialPortFlowControl.xonXoff,
  };
}
