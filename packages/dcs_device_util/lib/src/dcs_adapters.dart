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
      throw DcsDeviceConnectionException(
        'Could not open serial port ${device.portName}: '
        '${error?.message ?? 'unknown serial error'}',
        code: error?.errorCode,
      );
    }

    return _DcsSerialPortSession(port);
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
  _DcsSerialPortSession(this._port) {
    _reader = SerialPortReader(_port);
    _dataSubscription = _reader.stream.listen(
      _dataController.add,
      onError: _dataController.addError,
      onDone: _dataController.close,
    );
  }

  final SerialPort _port;
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

    final written = _port.write(Uint8List.fromList(bytes));
    if (written != bytes.length) {
      throw DcsDeviceConnectionException(
        'Serial port wrote $written of ${bytes.length} bytes.',
      );
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
