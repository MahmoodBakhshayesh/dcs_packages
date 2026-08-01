import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../aea_helpers.dart';
import '../cute_peripheral.dart';
import '../models.dart';
import 'arinc_defines.dart';
import 'arinc_rqb.dart';

/// ARINC / MUSE PCP32 peripheral over TCP.
class ArincDevice implements CutePeripheral {
  ArincDevice({
    required this.kind,
    required this.endpoint,
    required this.name,
    this.aeaContext = 'm/A,001',
    this.connectTimeout = const Duration(seconds: 10),
    this.ackTimeout = const Duration(seconds: 30),
  });

  @override
  final CutePeripheralKind kind;

  final CutePeripheralEndpoint endpoint;
  final String name;
  final String aeaContext;
  final Duration connectTimeout;
  final Duration ackTimeout;

  @override
  CuteVendor get vendor => CuteVendor.arinc;

  @override
  String get displayName => name;

  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  final _buffer = BytesBuilder(copy: false);
  final _statusController = StreamController<CutePeripheralStatus>.broadcast();
  final _dataController = StreamController<List<int>>.broadcast();
  final _pendingAcks = <int, Completer<ArincRqb>>{};

  CutePeripheralStatus _status = const CutePeripheralStatus(
    state: CutePeripheralState.disconnected,
    message: 'Disconnected',
  );

  @override
  Stream<CutePeripheralStatus> get statusChanges => _statusController.stream;

  @override
  CutePeripheralStatus get currentStatus => _status;

  @override
  Stream<List<int>> get data => _dataController.stream;

  @override
  Future<void> open() async {
    if (_socket != null) return;
    _setStatus(
      const CutePeripheralStatus(
        state: CutePeripheralState.connecting,
        message: 'Connecting to MUSE',
      ),
    );
    try {
      final socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: connectTimeout,
      );
      _socket = socket;
      _subscription = socket.listen(
        _onBytes,
        onError: (Object e, StackTrace st) {
          _setStatus(
            CutePeripheralStatus(
              state: CutePeripheralState.failed,
              message: e.toString(),
            ),
          );
        },
        onDone: () {
          _setStatus(
            const CutePeripheralStatus(
              state: CutePeripheralState.disconnected,
              message: 'Socket closed',
            ),
          );
          _socket = null;
        },
        cancelOnError: false,
      );

      await _sendAndWaitAck(
        ArincRqb.commandOnly(ArincPcpCommand.byteOrder),
        expectAck: ArincPcpCommand.byteOrder,
        treatSameCommandAsAck: true,
      );
      await _sendAndWaitAck(
        ArincRqb.commandOnly(
          ArincPcpCommand.mode,
          parameters: [ArincPcpMode.unsolicitedReadWrite, 0, 0, 0],
        ),
        expectAck: ArincPcpCommand.modeAck,
      );
      await _sendAndWaitAck(
        ArincRqb.commandOnly(ArincPcpCommand.status),
        expectAck: ArincPcpCommand.statusAck,
      );

      _setStatus(
        CutePeripheralStatus(
          state: CutePeripheralState.open,
          message: 'Connected to $endpoint ($aeaContext)',
          online: true,
        ),
      );
    } catch (e) {
      await close();
      _setStatus(
        CutePeripheralStatus(
          state: CutePeripheralState.failed,
          message: e.toString(),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> lock({Duration timeout = const Duration(seconds: 10)}) async {
    await _sendAndWaitAck(
      ArincRqb.commandOnly(ArincPcpCommand.lock),
      expectAck: ArincPcpCommand.lockAck,
      timeout: timeout,
    );
    _setStatus(_status.copyWith(state: CutePeripheralState.locked, locked: true, message: 'Locked'));
  }

  @override
  Future<void> unlock() async {
    await _sendAndWaitAck(
      ArincRqb.commandOnly(ArincPcpCommand.unlock),
      expectAck: ArincPcpCommand.unlockAck,
    );
    _setStatus(_status.copyWith(state: CutePeripheralState.open, locked: false, message: 'Unlocked'));
  }

  @override
  Future<void> write(List<int> bytes, {bool endDoc = false}) async {
    final wrapped = AeaHelpers.wrapArincAea(bytes);
    await _sendAndWaitAck(
      ArincRqb.send(wrapped),
      expectAck: ArincPcpCommand.sendAck,
    );
  }

  @override
  Future<void> writeAea(
    String command, {
    bool endDoc = false,
    bool frame = true,
  }) async {
    await write(AeaHelpers.asciiBytes(command), endDoc: endDoc);
  }

  @override
  Future<List<int>?> read({Duration timeout = const Duration(seconds: 5)}) async {
    final completer = Completer<List<int>>();
    late final StreamSubscription<List<int>> sub;
    sub = data.listen((event) {
      if (!completer.isCompleted) completer.complete(event);
    });
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<CutePeripheralStatus> queryStatus() async {
    final ack = await _sendAndWaitAck(
      ArincRqb.commandOnly(ArincPcpCommand.status),
      expectAck: ArincPcpCommand.statusAck,
    );
    final online = (ack.physicalStatus & ArincPhysicalStatus.online) == ArincPhysicalStatus.online ||
        ack.physicalStatus == ArincPhysicalStatus.online;
    final next = _status.copyWith(
      online: online,
      rawCode: ack.physicalStatus,
      message: 'Physical status ${ack.physicalStatus}',
    );
    _setStatus(next);
    return next;
  }

  @override
  Future<void> close() async {
    for (final pending in _pendingAcks.values) {
      if (!pending.isCompleted) {
        pending.completeError(const CutePeripheralFailure('Connection closed'));
      }
    }
    _pendingAcks.clear();
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    _buffer.clear();
    _setStatus(
      const CutePeripheralStatus(
        state: CutePeripheralState.disconnected,
        message: 'Disconnected',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await close();
    await _statusController.close();
    await _dataController.close();
  }

  Future<ArincRqb> _sendAndWaitAck(
    ArincRqb packet, {
    required int expectAck,
    Duration? timeout,
    bool treatSameCommandAsAck = false,
  }) async {
    final socket = _socket;
    if (socket == null) {
      throw const CutePeripheralFailure('ARINC device is not open');
    }
    final key = treatSameCommandAsAck ? packet.command : expectAck;
    final completer = Completer<ArincRqb>();
    _pendingAcks[key] = completer;
    socket.add(packet.encode());
    await socket.flush();
    try {
      return await completer.future.timeout(timeout ?? ackTimeout);
    } on TimeoutException {
      _pendingAcks.remove(key);
      throw CutePeripheralFailure(
        'Timed out waiting for ARINC ACK $expectAck on $name',
      );
    }
  }

  void _onBytes(List<int> chunk) {
    _buffer.add(chunk);
    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length < 16) return;
      final data = ByteData.sublistView(bytes);
      final dataLen = data.getUint16(10, Endian.little);
      final total = 16 + dataLen;
      if (bytes.length < total) return;
      final packetBytes = bytes.sublist(0, total);
      final remain = bytes.sublist(total);
      _buffer.clear();
      if (remain.isNotEmpty) _buffer.add(remain);

      final packet = ArincRqb.decode(packetBytes);
      final pending = _pendingAcks.remove(packet.command);
      if (pending != null && !pending.isCompleted) {
        pending.complete(packet);
      }
      if (packet.body.isNotEmpty) {
        final body = packet.body;
        final payload = body.length >= 2 && body[0] == 0x61 && body[1] == 0x2f
            ? body.sublist(2)
            : body;
        if (!_dataController.isClosed) {
          _dataController.add(payload);
        }
      }
    }
  }

  void _setStatus(CutePeripheralStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
