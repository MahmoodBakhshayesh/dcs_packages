import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'cupps_models.dart';

abstract interface class CuppsTransport {
  Stream<List<int>> get incoming;

  bool get isOpen;

  Future<void> connect(CuppsEndpoint endpoint, {required Duration timeout});

  Future<void> write(List<int> bytes);

  Future<void> close();
}

class SocketCuppsTransport implements CuppsTransport {
  SocketCuppsTransport();

  final _incomingController = StreamController<List<int>>.broadcast();
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;

  @override
  Stream<List<int>> get incoming => _incomingController.stream;

  @override
  bool get isOpen => _socket != null;

  @override
  Future<void> connect(
    CuppsEndpoint endpoint, {
    required Duration timeout,
  }) async {
    await close();
    final socket = await Socket.connect(
      endpoint.host,
      endpoint.port,
      timeout: timeout,
    );
    _socket = socket;
    _subscription = socket.listen(
      _incomingController.add,
      onError: _incomingController.addError,
      onDone: () {
        _socket = null;
        _incomingController.addError(
          const CuppsRequestFailure('Socket closed by remote host.'),
        );
      },
      cancelOnError: true,
    );
  }

  @override
  Future<void> write(List<int> bytes) async {
    final socket = _socket;
    if (socket == null) {
      throw const CuppsRequestFailure('Socket is not connected.');
    }
    socket.add(bytes);
    await socket.flush();
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    socket?.destroy();
  }

  Future<void> dispose() async {
    await close();
    await _incomingController.close();
  }
}
