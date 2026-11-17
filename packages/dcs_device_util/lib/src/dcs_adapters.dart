import 'dart:async';
import 'dart:io';

import 'dcs_models.dart';

// Serial ports use libserialport (`dart:ffi`), which does not exist on web.
export 'dcs_serial_port_adapter_stub.dart'
    if (dart.library.ffi) 'dcs_serial_port_adapter_ffi.dart';

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
    try {
      _socket.add(bytes);
      await _socket.flush();
    } catch (error) {
      _closed = true;
      throw DcsDeviceConnectionException('LAN write failed: $error');
    }
  }

  @override
  Future<void> ping() async {
    if (!isOpen) {
      throw const DcsDeviceConnectionException('LAN socket is not open.');
    }
    try {
      // Accessing remoteAddress throws when the peer is gone.
      // ignore: unnecessary_statements
      _socket.remoteAddress;
    } catch (error) {
      _closed = true;
      throw DcsDeviceConnectionException(
        'LAN socket is no longer healthy: $error',
      );
    }
  }

  var _released = false;

  @override
  Future<void> close() async {
    _closed = true;
    if (_released) return;
    _released = true;
    try {
      await _dataSubscription.cancel();
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {}
    if (!_dataController.isClosed) {
      await _dataController.close();
    }
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
