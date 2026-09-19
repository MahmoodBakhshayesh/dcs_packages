import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'dcs_models.dart';

/// Transport adapter used by the controller to discover and connect devices.
abstract class DcsDeviceAdapter {
  DcsDeviceTransport get transport;

  Future<List<DcsDiscoveredDevice>> discover();

  Future<DcsDeviceSession> connect(
    DcsDeviceProfile profile,
    DcsDiscoveredDevice device,
  );
}

/// An open device connection.
abstract class DcsDeviceSession {
  Stream<List<int>> get data;

  bool get isOpen;

  Future<void> write(List<int> bytes);

  /// Lightweight health check. Implementations should throw when not healthy.
  Future<void> ping();

  Future<void> close();
}

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

/// Minimal TCP adapter for LAN Standalone profiles.
class DcsNetworkPortAdapter implements DcsDeviceAdapter {
  const DcsNetworkPortAdapter();

  @override
  DcsDeviceTransport get transport => DcsDeviceTransport.network;

  @override
  Future<List<DcsDiscoveredDevice>> discover() async => const [];

  @override
  Future<DcsDeviceSession> connect(
    DcsDeviceProfile profile,
    DcsDiscoveredDevice device,
  ) async {
    final host = profile.lan.host.trim().isNotEmpty
        ? profile.lan.host.trim()
        : device.portName;
    final port = profile.lan.port > 0
        ? profile.lan.port
        : int.tryParse(device.metadata['port'] ?? '') ?? 0;
    if (host.isEmpty || port <= 0) {
      throw const DcsDeviceConnectionException(
        'LAN host and port are required.',
      );
    }

    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: profile.serialOptions.writeTimeout,
      );
      return _DcsNetworkSession(socket);
    } catch (error) {
      throw DcsDeviceConnectionException(
        'Could not open LAN $host:$port — $error',
      );
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
      final written = _port.write(chunk, timeout: timeoutMs);
      if (written < 0) {
        final error = SerialPort.lastError;
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
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _dataSubscription.cancel();
    _reader.close();
    _port.close();
    _port.dispose();
    await _dataController.close();
  }
}

class _DcsNetworkSession implements DcsDeviceSession {
  _DcsNetworkSession(this._socket) {
    _dataSubscription = _socket.listen(
      _dataController.add,
      onError: _dataController.addError,
      onDone: _dataController.close,
      cancelOnError: false,
    );
  }

  final Socket _socket;
  final StreamController<List<int>> _dataController =
      StreamController.broadcast();
  late final StreamSubscription<List<int>> _dataSubscription;
  var _closed = false;

  @override
  Stream<List<int>> get data => _dataController.stream;

  @override
  bool get isOpen => !_closed;

  @override
  Future<void> write(List<int> bytes) async {
    if (!isOpen) {
      throw const DcsDeviceConnectionException('LAN socket is closed.');
    }
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<void> ping() async {
    if (!isOpen) {
      throw const DcsDeviceConnectionException('LAN socket is not open.');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _dataSubscription.cancel();
    await _socket.close();
    await _dataController.close();
  }
}

class DcsDeviceConnectionException implements Exception {
  const DcsDeviceConnectionException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() {
    final suffix = code == null ? '' : ' (code: $code)';
    return 'DcsDeviceConnectionException: $message$suffix';
  }
}

/// Windows LPT (parallel / document printer) adapter for DCP text.
///
/// Opens `\\.\LPTn` for raw write. Discovery always offers LPT1–LPT3; the OS
/// reports Access Denied / not found only when connecting.
class DcsLptPortAdapter implements DcsDeviceAdapter {
  const DcsLptPortAdapter();

  static const candidatePorts = ['LPT1', 'LPT2', 'LPT3'];

  @override
  DcsDeviceTransport get transport => DcsDeviceTransport.parallel;

  @override
  Future<List<DcsDiscoveredDevice>> discover() async {
    return [
      for (final name in candidatePorts)
        DcsDiscoveredDevice(
          id: 'lpt:$name',
          portName: name,
          transport: DcsDeviceTransport.parallel,
          productName: 'Parallel port',
          metadata: const {'kind': 'lpt'},
        ),
    ];
  }

  @override
  Future<DcsDeviceSession> connect(
    DcsDeviceProfile profile,
    DcsDiscoveredDevice device,
  ) async {
    if (profile.connectionType != DcsConnectionType.lpt &&
        profile.transport != DcsDeviceTransport.parallel) {
      throw const DcsDeviceConnectionException(
        'LPT adapter requires an LPT / parallel profile.',
      );
    }

    final name = DcsLptPortAdapter.normalizeLptName(
      profile.comPort?.trim().isNotEmpty == true
          ? profile.comPort!.trim()
          : device.portName,
    );
    if (name == null) {
      throw DcsDeviceConnectionException(
        'Invalid LPT port "${device.portName}". Use LPT1–LPT3.',
      );
    }

    try {
      // Windows device namespace path — required for legacy parallel ports.
      final resolvedPath =
          Platform.isWindows ? '\\\\.\\$name' : '/dev/${name.toLowerCase()}';
      final raf = await File(resolvedPath).open(mode: FileMode.write);
      return _DcsLptSession(raf, name);
    } catch (error) {
      throw DcsDeviceConnectionException(
        'Could not open LPT port $name — $error',
      );
    }
  }

  /// Accepts LPT1 / lpt1 / LTP1 (common typo) → `LPT1`.
  static String? normalizeLptName(String raw) {
    final upper = raw.trim().toUpperCase().replaceAll(r'\\.\', '');
    final match = RegExp(r'^(LPT|LTP)(\d+)$').firstMatch(upper);
    if (match == null) return null;
    return 'LPT${match.group(2)}';
  }
}

class _DcsLptSession implements DcsDeviceSession {
  _DcsLptSession(this._raf, this.portName);

  final RandomAccessFile _raf;
  final String portName;
  final StreamController<List<int>> _dataController =
      StreamController.broadcast();
  var _closed = false;

  @override
  Stream<List<int>> get data => _dataController.stream;

  @override
  bool get isOpen => !_closed;

  @override
  Future<void> write(List<int> bytes) async {
    if (!isOpen) {
      throw const DcsDeviceConnectionException('LPT port is closed.');
    }
    await _raf.writeFrom(bytes);
    await _raf.flush();
  }

  @override
  Future<void> ping() async {
    if (!isOpen) {
      throw const DcsDeviceConnectionException('LPT port is not open.');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _raf.close();
    } catch (_) {}
    await _dataController.close();
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
