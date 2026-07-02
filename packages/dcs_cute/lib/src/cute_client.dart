// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'cute_logger.dart';
import 'cute_matip_codec.dart';
import 'cute_models.dart';
import 'cute_transport.dart';

typedef CuteTransportFactory = CuteTransport Function();

class CuteClient {
  CuteClient({
    CuteConnectionOptions options = const CuteConnectionOptions(),
    CuteTransportFactory transportFactory = _defaultTransportFactory,
    CuteLogger? logger,
  }) : _options = options,
       _transportFactory = transportFactory,
       logger = logger ?? CuteLogger();

  final CuteConnectionOptions _options;
  final CuteTransportFactory _transportFactory;
  final CuteLogger logger;
  final _codec = const CuteMatipCodec();
  final _decoder = CuteMatipDecoder();
  final _statusController = StreamController<CuteSessionStatus>.broadcast();
  final _messageController = StreamController<CuteMessage>.broadcast();

  CuteTransport? _transport;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _openCompleter;
  CuteSessionConfig? _config;
  var _status = const CuteSessionStatus.idle();

  Stream<CuteSessionStatus> get status => _statusController.stream;

  CuteSessionStatus get currentStatus => _status;

  Stream<CuteMessage> get messages => _messageController.stream;

  bool get isOpen => _status.state == CuteSessionState.open;

  Future<void> connect({
    required CuteEndpoint endpoint,
    required CuteSessionConfig config,
  }) async {
    config.validate();
    _config = config;
    _setStatus(
      CuteSessionState.connecting,
      'Connecting to CUTE/MATIP endpoint $endpoint.',
      endpoint: endpoint,
      clearError: true,
    );

    final transport = _transportFactory();
    _transport = transport;
    _subscription = transport.incoming.listen(
      _onBytes,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );

    await transport.connect(endpoint, timeout: _options.connectTimeout);
    _setStatus(
      CuteSessionState.tcpConnected,
      'TCP socket connected.',
      endpoint: endpoint,
      clearError: true,
    );

    _setStatus(
      CuteSessionState.openingSession,
      'Opening MATIP session.',
      endpoint: endpoint,
      clearError: true,
    );
    final openCompleter = Completer<void>();
    _openCompleter = openCompleter;
    await transport.write(_codec.sessionOpen(config));
    logger(
      CuteLogLevel.debug,
      CuteLogScope.matip,
      'Session Open sent.',
      direction: CuteMessageDirection.outbound,
      data: {
        'trafficType': config.trafficType.name,
        'subtype': config.subtype.name,
      },
    );

    await openCompleter.future.timeout(
      _options.sessionOpenTimeout,
      onTimeout: () {
        _openCompleter = null;
        throw const CuteProtocolFailure('MATIP Session Open timed out.');
      },
    );

    _setStatus(
      CuteSessionState.open,
      'MATIP session open.',
      endpoint: endpoint,
      clearError: true,
    );
  }

  Future<void> send(List<int> payload, {List<int> id = const []}) async {
    final config = _requireOpenConfig();
    final transport = _requireOpenTransport();
    await transport.write(_codec.data(config, payload: payload, id: id));
    logger(
      CuteLogLevel.debug,
      CuteLogScope.matip,
      'Data packet sent.',
      direction: CuteMessageDirection.outbound,
      data: {'bytes': payload.length, 'idBytes': id.length},
    );
  }

  Future<void> sendText(
    String text, {
    List<int> id = const [],
    Encoding encoding = ascii,
  }) {
    return send(encoding.encode(text), id: id);
  }

  Future<void> close({int cause = 0}) async {
    final transport = _transport;
    if (transport == null) return;
    _setStatus(CuteSessionState.closing, 'Closing MATIP session.');
    if (transport.isOpen) {
      await transport.write(_codec.sessionClose(cause: cause));
    }
    await _subscription?.cancel();
    _subscription = null;
    await transport.close();
    _transport = null;
    _openCompleter = null;
    _setStatus(CuteSessionState.closed, 'CUTE/MATIP session closed.');
  }

  Future<void> dispose() async {
    await close();
    await _statusController.close();
    await _messageController.close();
    await logger.close();
  }

  void _onBytes(List<int> bytes) {
    _decoder.add(bytes);
    for (final packet in _decoder.takePackets()) {
      logger(
        CuteLogLevel.debug,
        CuteLogScope.matip,
        'Packet received.',
        direction: CuteMessageDirection.inbound,
        data: {
          'command': packet.command.name,
          'payloadBytes': packet.payload.length,
        },
      );
      _handlePacket(packet);
    }
  }

  void _handlePacket(CuteMatipPacket packet) {
    switch (packet.command) {
      case CuteMatipCommand.openConfirm:
        final completer = _openCompleter;
        _openCompleter = null;
        if (packet.isAcceptedOpenConfirm) {
          completer?.complete();
        } else {
          completer?.completeError(
            CuteProtocolFailure(
              'MATIP session refused.',
              cause: packet.refusalCause,
            ),
          );
        }
      case CuteMatipCommand.sessionOpen:
        final transport = _requireOpenTransport(allowOpening: true);
        transport.write(_codec.openConfirmAccepted(_config)).ignore();
      case CuteMatipCommand.sessionClose:
        _setStatus(
          CuteSessionState.closed,
          'Remote host closed MATIP session.',
          lastError: packet.closeCause,
        );
      case CuteMatipCommand.data:
        final config = _config;
        if (config == null) {
          throw const CuteProtocolFailure(
            'Received data before configuration.',
          );
        }
        _messageController.add(_codec.decodeData(config, packet));
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    logger(
      CuteLogLevel.error,
      CuteLogScope.socket,
      'Socket error.',
      error: error,
      stackTrace: stackTrace,
    );
    _openCompleter?.completeError(error);
    _openCompleter = null;
    _setStatus(CuteSessionState.failed, 'Socket error.', lastError: error);
  }

  void _onDone() {
    _openCompleter?.completeError(
      const CuteProtocolFailure('Socket closed before MATIP session opened.'),
    );
    _openCompleter = null;
    _setStatus(CuteSessionState.closed, 'Socket closed.');
  }

  CuteSessionConfig _requireOpenConfig() {
    final config = _config;
    if (config == null || !isOpen) {
      throw const CuteProtocolFailure('MATIP session is not open.');
    }
    return config;
  }

  CuteTransport _requireOpenTransport({bool allowOpening = false}) {
    final transport = _transport;
    final stateOk = allowOpening || isOpen;
    if (transport == null || !transport.isOpen || !stateOk) {
      throw const CuteProtocolFailure('Socket is not open.');
    }
    return transport;
  }

  void _setStatus(
    CuteSessionState state,
    String message, {
    CuteEndpoint? endpoint,
    Object? lastError,
    bool clearError = false,
  }) {
    _status = _status.copyWith(
      state: state,
      message: message,
      endpoint: endpoint,
      lastError: lastError,
      clearError: clearError,
    );
    _statusController.add(_status);
    logger(
      lastError == null ? CuteLogLevel.info : CuteLogLevel.warning,
      CuteLogScope.lifecycle,
      message,
      data: {'state': state.name},
      error: lastError,
    );
  }
}

CuteTransport _defaultTransportFactory() => SocketCuteTransport();
