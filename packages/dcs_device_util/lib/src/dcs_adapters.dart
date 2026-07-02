import 'dart:async';
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
    final port = SerialPort(device.portName);
    final config = SerialPortConfig()
      ..baudRate = profile.serialOptions.baudRate
      ..bits = profile.serialOptions.dataBits
      ..stopBits = profile.serialOptions.stopBits
      ..parity = profile.serialOptions.parity;
    config.setFlowControl(_flowControlValue(profile.serialOptions.flowControl));

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
    DcsSerialFlowControl.rtsCts => SerialPortFlowControl.rtsCts,
    DcsSerialFlowControl.dtrDsr => SerialPortFlowControl.dtrDsr,
  };
}
