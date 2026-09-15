// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../zebra_logger.dart';
import '../zebra_models.dart';
import 'zebra_transport.dart';

class TcpZebraTransport implements ZebraTransport {
  TcpZebraTransport({
    required this.endpoint,
    ZebraLogger? logger,
    this.printerId,
  }) : _logger = logger;

  final ZebraEndpoint endpoint;
  final ZebraLogger? _logger;
  final String? printerId;

  Socket? _socket;
  final _incoming = <int>[];
  StreamSubscription<List<int>>? _subscription;

  @override
  ZebraConnectionType get connectionType => ZebraConnectionType.tcp;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> connect({Duration? timeout}) async {
    await disconnect();
    _logger?.call(
      ZebraLogLevel.info,
      ZebraLogScope.transport,
      'Connecting TCP ${endpoint.host}:${endpoint.port}',
      printerId: printerId,
    );
    try {
      _socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: timeout ?? const Duration(seconds: 10),
      );
      _subscription = _socket!.listen(
        (data) => _incoming.addAll(data),
        onError: (Object error, StackTrace stack) {
          _logger?.call(
            ZebraLogLevel.error,
            ZebraLogScope.transport,
            'TCP socket error',
            printerId: printerId,
            error: error,
            stackTrace: stack,
          );
        },
        onDone: () {
          _logger?.call(
            ZebraLogLevel.info,
            ZebraLogScope.transport,
            'TCP socket closed',
            printerId: printerId,
          );
          _socket = null;
        },
        cancelOnError: false,
      );
      _logger?.call(
        ZebraLogLevel.info,
        ZebraLogScope.transport,
        'TCP connected',
        printerId: printerId,
        data: {'endpoint': endpoint.toString()},
      );
    } catch (error, stack) {
      _logger?.call(
        ZebraLogLevel.error,
        ZebraLogScope.transport,
        'TCP connect failed',
        printerId: printerId,
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    _incoming.clear();
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
      socket.destroy();
    }
  }

  @override
  Future<void> write(Uint8List data, {Duration? timeout}) async {
    final socket = _socket;
    if (socket == null) {
      throw const ZebraRequestFailure('TCP transport is not connected.');
    }
    _logger?.call(
      ZebraLogLevel.debug,
      ZebraLogScope.transport,
      'TCP write ${data.length} bytes',
      printerId: printerId,
      direction: ZebraMessageDirection.outbound,
    );
    socket.add(data);
    await socket.flush().timeout(timeout ?? const Duration(seconds: 30));
  }

  @override
  Future<Uint8List?> read({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_socket == null) return null;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_incoming.isNotEmpty) {
        final bytes = Uint8List.fromList(_incoming);
        _incoming.clear();
        _logger?.call(
          ZebraLogLevel.debug,
          ZebraLogScope.transport,
          'TCP read ${bytes.length} bytes',
          printerId: printerId,
          direction: ZebraMessageDirection.inbound,
        );
        return bytes;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return null;
  }
}
