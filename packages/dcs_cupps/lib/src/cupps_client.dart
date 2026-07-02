// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'cupps_device.dart';
import 'cupps_framing.dart';
import 'cupps_logger.dart';
import 'cupps_models.dart';
import 'cupps_transport.dart';
import 'cupps_xml.dart';

typedef CuppsTransportFactory = CuppsTransport Function();

class CuppsClient implements CuppsDeviceCommandSender {
  CuppsClient({
    CuppsConnectionOptions options = const CuppsConnectionOptions(),
    CuppsTransportFactory transportFactory = _defaultTransportFactory,
    CuppsLogger? logger,
    CuppsStopCommandHandler? onStopCommand,
  }) : _options = options,
       _transportFactory = transportFactory,
       logger = logger ?? CuppsLogger(),
       _onStopCommand = onStopCommand;

  final CuppsConnectionOptions _options;
  final CuppsTransportFactory _transportFactory;
  final CuppsStopCommandHandler? _onStopCommand;
  final CuppsLogger logger;

  final _platformStatusController =
      StreamController<CuppsPlatformStatus>.broadcast();
  final _deviceStatusesController =
      StreamController<Map<String, CuppsDeviceStatus>>.broadcast();
  final _deviceStatusControllers =
      <String, StreamController<CuppsDeviceStatus>>{};
  final _devices = <String, CuppsDevice>{};
  final _deviceStatuses = <String, CuppsDeviceStatus>{};
  final _deviceSessions = <String, _CuppsSocketSession>{};

  _CuppsSocketSession? _platformSession;
  CuppsApplicationInfo? _application;
  String? _eventToken;
  String? _applicationToken;
  String? _deviceToken;
  Timer? _heartbeatTimer;
  var _platformStatus = const CuppsPlatformStatus.idle();

  Stream<CuppsPlatformStatus> get platformStatus =>
      _platformStatusController.stream;

  CuppsPlatformStatus get currentPlatformStatus => _platformStatus;

  Stream<Map<String, CuppsDeviceStatus>> get deviceStatuses =>
      _deviceStatusesController.stream;

  Map<String, CuppsDeviceStatus> get currentDeviceStatuses =>
      Map.unmodifiable(_deviceStatuses);

  List<CuppsDevice> get devices => List.unmodifiable(_devices.values);

  String? get deviceToken => _deviceToken;

  Future<void> connect({
    required CuppsEndpoint endpoint,
    required CuppsApplicationInfo application,
  }) async {
    _application = application;
    _setPlatformStatus(
      CuppsPlatformState.connecting,
      'Connecting to CUPPS platform $endpoint.',
      endpoint: endpoint,
      clearError: true,
    );

    final session = _CuppsSocketSession(
      name: 'Platform',
      scope: CuppsLogScope.platform,
      transport: _transportFactory(),
      logger: logger,
      onUnmatchedMessage: _handlePlatformMessage,
      onClosed: () => _handlePlatformClosed('Platform socket closed.'),
    );
    _platformSession = session;
    await session.connect(endpoint, timeout: _options.connectTimeout);
    _setPlatformStatus(
      CuppsPlatformState.connected,
      'Platform socket connected.',
      endpoint: endpoint,
      clearError: true,
    );
  }

  Future<void> authenticate() async {
    final application = _application;
    if (application == null) {
      throw const CuppsRequestFailure('Application info is not configured.');
    }

    _setPlatformStatus(
      CuppsPlatformState.authenticating,
      'Authenticating with CUPPS platform.',
      clearError: true,
    );

    final interfaceLevels = await sendPlatformRequest(
      (messageId) => CuppsXml.interfaceLevelsAvailableRequest(
        messageId: messageId,
        hsXsdVersion: _options.hsXsdVersion,
      ),
    );
    final levels = CuppsXml.interfaceLevels(interfaceLevels.rawXml);
    if (!levels.contains(_options.interfaceLevel)) {
      throw CuppsRequestFailure(
        'Interface level ${_options.interfaceLevel} is not available.',
      );
    }

    final selectedLevel = await sendPlatformRequest(
      (messageId) => CuppsXml.interfaceLevelRequest(
        messageId: messageId,
        level: _options.interfaceLevel,
      ),
    );
    if (!selectedLevel.ok) {
      throw CuppsRequestFailure(
        'Interface level selection failed: ${selectedLevel.result}',
      );
    }

    _eventToken = _randomToken(16);
    _applicationToken = _randomToken(32);
    final auth = await sendPlatformRequest(
      (messageId) => CuppsXml.authenticateRequest(
        messageId: messageId,
        application: application,
        eventToken: _eventToken!,
        platformDefinedParameter: _applicationToken!,
      ),
    );
    if (!auth.ok) {
      throw CuppsRequestFailure('Authentication failed: ${auth.result}');
    }

    _deviceToken = CuppsXml.deviceToken(auth.rawXml);
    final descriptors = CuppsXml.devicesFromAuthenticateResponse(auth.rawXml)
        .where((device) => _options.requiredDeviceTypes.contains(device.type))
        .toList(growable: false);

    _devices
      ..clear()
      ..addEntries(
        descriptors.map(
          (descriptor) => MapEntry(
            descriptor.id,
            CuppsDevice(descriptor: descriptor, sender: this),
          ),
        ),
      );

    for (final descriptor in descriptors) {
      updateDeviceStatus(
        descriptor,
        CuppsDeviceState.discovered,
        'Device discovered at ${descriptor.endpoint}.',
        clearError: true,
      );
    }

    _setPlatformStatus(
      CuppsPlatformState.authenticated,
      'Authenticated. ${descriptors.length} supported device(s) discovered.',
      authenticated: true,
      interfaceLevel: _options.interfaceLevel,
      clearError: true,
    );
  }

  Future<void> connectDevices() async {
    _setPlatformStatus(
      CuppsPlatformState.discoveringDevices,
      'Connecting to discovered devices.',
      clearError: true,
    );

    for (final device in _devices.values) {
      await _connectDevice(device.descriptor);
    }

    _setPlatformStatus(
      CuppsPlatformState.ready,
      'CUPPS platform and devices are ready.',
      clearError: true,
    );
    _startHeartbeat();
  }

  Future<CuppsCommandResult> sendPlatformRequest(
    String Function(int messageId) buildXml, {
    Duration? timeout,
  }) async {
    final session = _platformSession;
    if (session == null || !session.isOpen) {
      throw const CuppsRequestFailure('Platform socket is not connected.');
    }
    final xml = await session.request(
      buildXml,
      timeout ?? _options.requestTimeout,
    );
    return _resultFromXml(xml);
  }

  @override
  Future<CuppsCommandResult> sendDeviceRequest(
    CuppsDeviceDescriptor device,
    String Function(int messageId) buildXml, {
    Duration? timeout,
    CuppsDeviceState? busyState,
    String? busyMessage,
  }) async {
    var session = _deviceSessions[device.id];
    if (session == null || !session.isOpen) {
      await _connectDevice(device);
      session = _deviceSessions[device.id];
    }
    if (session == null || !session.isOpen) {
      throw CuppsRequestFailure('Device ${device.name} is not connected.');
    }

    if (busyState != null) {
      updateDeviceStatus(
        device,
        busyState,
        busyMessage ?? 'Sending device request.',
        clearError: true,
      );
    }

    try {
      final xml = await session.request(
        buildXml,
        timeout ?? _options.requestTimeout,
      );
      final result = _resultFromXml(xml);
      if (!result.ok) {
        updateDeviceStatus(
          device,
          CuppsDeviceState.degraded,
          result.message ?? 'Device request failed: ${result.result}.',
          error: result.result,
          clearError: false,
        );
      } else if (busyState != null) {
        updateDeviceStatus(
          device,
          CuppsDeviceState.initialized,
          'Device request completed.',
          initialized: true,
          clearError: true,
        );
      }
      return result;
    } catch (error) {
      updateDeviceStatus(
        device,
        CuppsDeviceState.failed,
        'Device request failed.',
        error: error,
        clearError: false,
      );
      rethrow;
    }
  }

  @override
  Stream<CuppsDeviceStatus> deviceStatus(String deviceId) {
    return _deviceStatusControllers
        .putIfAbsent(deviceId, () => StreamController.broadcast())
        .stream;
  }

  @override
  CuppsDeviceStatus? currentDeviceStatus(String deviceId) {
    return _deviceStatuses[deviceId];
  }

  @override
  void updateDeviceStatus(
    CuppsDeviceDescriptor device,
    CuppsDeviceState state,
    String message, {
    bool? locked,
    bool? acquired,
    bool? initialized,
    Object? error,
    bool clearError = false,
  }) {
    final previous = _deviceStatuses[device.id];
    final status = previous == null
        ? CuppsDeviceStatus(
            device: device,
            state: state,
            message: message,
            locked: locked ?? false,
            acquired: acquired ?? false,
            initialized: initialized ?? false,
            lastChangedAt: DateTime.now(),
            lastError: clearError ? null : error,
          )
        : previous.copyWith(
            state: state,
            message: message,
            locked: locked,
            acquired: acquired,
            initialized: initialized,
            lastChangedAt: DateTime.now(),
            lastError: error,
            clearError: clearError,
          );
    _deviceStatuses[device.id] = status;
    _deviceStatusesController.add(Map.unmodifiable(_deviceStatuses));
    _deviceStatusControllers[device.id]?.add(status);
    logger(
      error == null ? CuppsLogLevel.info : CuppsLogLevel.warning,
      CuppsLogScope.device,
      message,
      deviceId: device.id,
      error: error,
      data: {'state': state.name, 'deviceName': device.name},
    );
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _setPlatformStatus(
      CuppsPlatformState.disconnecting,
      'Disconnecting CUPPS platform and devices.',
    );

    for (final session in _deviceSessions.values) {
      await session.close();
    }
    _deviceSessions.clear();
    await _platformSession?.close();
    _platformSession = null;

    for (final status in _deviceStatuses.values.toList()) {
      updateDeviceStatus(
        status.device,
        CuppsDeviceState.disconnected,
        'Device disconnected.',
        locked: false,
        acquired: false,
      );
    }

    _setPlatformStatus(
      CuppsPlatformState.disconnected,
      'Disconnected.',
      authenticated: false,
    );
  }

  Future<void> dispose() async {
    await disconnect();
    await _platformStatusController.close();
    await _deviceStatusesController.close();
    for (final controller in _deviceStatusControllers.values) {
      await controller.close();
    }
    await logger.close();
  }

  Future<void> _connectDevice(CuppsDeviceDescriptor device) async {
    updateDeviceStatus(
      device,
      CuppsDeviceState.connecting,
      'Connecting to ${device.endpoint}.',
      clearError: true,
    );

    final session = _CuppsSocketSession(
      name: 'Device ${device.name}',
      scope: CuppsLogScope.device,
      deviceId: device.id,
      transport: _transportFactory(),
      logger: logger,
      onUnmatchedMessage: (message) => _handleDeviceMessage(device, message),
      onClosed: () {
        _deviceSessions.remove(device.id);
        updateDeviceStatus(
          device,
          CuppsDeviceState.disconnected,
          'Device socket closed.',
          locked: false,
          acquired: false,
        );
      },
    );

    try {
      await session.connect(device.endpoint, timeout: _options.connectTimeout);
      _deviceSessions[device.id] = session;
      updateDeviceStatus(
        device,
        CuppsDeviceState.connected,
        'Device socket connected.',
        clearError: true,
      );
    } catch (error) {
      updateDeviceStatus(
        device,
        CuppsDeviceState.failed,
        'Device connection failed.',
        error: error,
      );
      rethrow;
    }
  }

  Future<void> _handlePlatformMessage(CuppsEnvelope message) async {
    if (message.messageName == 'applicationStopCommandRequest') {
      final command = CuppsXml.stopCommand(message.rawXml);
      final decision = command == null
          ? CuppsStopCommandDecision.defer
          : await Future.value(
              _onStopCommand?.call(command) ?? CuppsStopCommandDecision.defer,
            );
      await _platformSession?.respond(
        CuppsXml.applicationStopCommandResponse(
          messageId: message.messageId,
          decision: decision,
        ),
      );
      if (decision == CuppsStopCommandDecision.forceClose) {
        await disconnect();
      }
      return;
    }

    if (message.messageName == 'notify') {
      logger(
        CuppsLogLevel.info,
        CuppsLogScope.platform,
        'Platform notification received.',
        messageId: message.messageId,
        xml: message.rawXml,
      );
    }
  }

  Future<void> _handleDeviceMessage(
    CuppsDeviceDescriptor device,
    CuppsEnvelope message,
  ) async {
    logger(
      CuppsLogLevel.info,
      CuppsLogScope.device,
      'Device message received.',
      deviceId: device.id,
      messageId: message.messageId,
      xml: message.rawXml,
    );
    if (message.messageName == 'notify') {
      updateDeviceStatus(
        device,
        CuppsDeviceState.dataAvailable,
        'Device data/notification received.',
        clearError: true,
      );
    }
  }

  void _handlePlatformClosed(String message) {
    _setPlatformStatus(
      CuppsPlatformState.disconnected,
      message,
      authenticated: false,
    );
    for (final status in _deviceStatuses.values.toList()) {
      updateDeviceStatus(
        status.device,
        CuppsDeviceState.disconnected,
        'Platform disconnected.',
        locked: false,
        acquired: false,
      );
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!_options.autoReconnect) return;
    _heartbeatTimer = Timer.periodic(_options.heartbeatInterval, (_) async {
      try {
        await sendPlatformRequest(
          (messageId) => CuppsXml.deviceQueryRequest(messageId: messageId),
          timeout: _options.heartbeatTimeout,
        );
      } catch (error, stackTrace) {
        logger(
          CuppsLogLevel.warning,
          CuppsLogScope.lifecycle,
          'Platform heartbeat failed.',
          error: error,
          stackTrace: stackTrace,
        );
        _setPlatformStatus(
          CuppsPlatformState.degraded,
          'Platform heartbeat failed.',
          lastError: error,
        );
      }
    });
  }

  CuppsCommandResult _resultFromXml(String xml) {
    final result = CuppsXml.result(xml);
    return CuppsCommandResult(
      ok: result.isEmpty || result.toLowerCase() == 'ok',
      result: result,
      rawXml: xml,
      message: result.isEmpty ? null : result,
    );
  }

  void _setPlatformStatus(
    CuppsPlatformState state,
    String message, {
    CuppsEndpoint? endpoint,
    bool? authenticated,
    String? interfaceLevel,
    Object? lastError,
    bool clearError = false,
  }) {
    _platformStatus = _platformStatus.copyWith(
      state: state,
      message: message,
      endpoint: endpoint,
      authenticated: authenticated,
      interfaceLevel: interfaceLevel,
      lastError: lastError,
      clearError: clearError,
    );
    _platformStatusController.add(_platformStatus);
    logger(
      lastError == null ? CuppsLogLevel.info : CuppsLogLevel.warning,
      CuppsLogScope.lifecycle,
      message,
      error: lastError,
      data: {'state': state.name},
    );
  }

  static String _randomToken(int length) {
    const alphabet = '0123456789abcdef';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
      growable: false,
    ).join();
  }
}

CuppsTransport _defaultTransportFactory() => SocketCuppsTransport();

class _CuppsSocketSession {
  _CuppsSocketSession({
    required this.name,
    required this.scope,
    required this.transport,
    required this.logger,
    required this.onUnmatchedMessage,
    required this.onClosed,
    this.deviceId,
  });

  final String name;
  final CuppsLogScope scope;
  final String? deviceId;
  final CuppsTransport transport;
  final CuppsLogger logger;
  final FutureOr<void> Function(CuppsEnvelope message) onUnmatchedMessage;
  final void Function() onClosed;

  final _codec = const CuppsFrameCodec();
  final _decoder = CuppsFrameDecoder();
  final _pending = <int, Completer<String>>{};
  StreamSubscription<List<int>>? _subscription;
  var _messageId = 1;
  var _closed = false;

  bool get isOpen => !_closed && transport.isOpen;

  Future<void> connect(
    CuppsEndpoint endpoint, {
    required Duration timeout,
  }) async {
    _closed = false;
    _subscription = transport.incoming.listen(
      _onBytes,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
    await transport.connect(endpoint, timeout: timeout);
    logger(
      CuppsLogLevel.info,
      CuppsLogScope.socket,
      '$name socket connected.',
      deviceId: deviceId,
      data: {'endpoint': endpoint.toString()},
    );
  }

  Future<String> request(
    String Function(int messageId) buildXml,
    Duration timeout,
  ) async {
    if (!isOpen) {
      throw CuppsRequestFailure('$name socket is not connected.');
    }

    final messageId = _nextMessageId();
    final xml = buildXml(messageId);
    final completer = Completer<String>();
    _pending[messageId] = completer;

    logger(
      CuppsLogLevel.debug,
      scope,
      '$name request sent.',
      direction: CuppsMessageDirection.outbound,
      deviceId: deviceId,
      messageId: messageId,
      xml: xml,
    );

    await transport.write(_codec.encode(xml));
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(messageId);
        throw CuppsRequestFailure('$name request $messageId timed out.');
      },
    );
  }

  Future<void> respond(String xml) async {
    logger(
      CuppsLogLevel.debug,
      scope,
      '$name response sent.',
      direction: CuppsMessageDirection.outbound,
      deviceId: deviceId,
      xml: xml,
    );
    await transport.write(_codec.encode(xml));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await transport.close();
    _failPending(CuppsRequestFailure('$name socket closed.'));
  }

  int _nextMessageId() {
    final id = _messageId;
    _messageId = (_messageId % (minPlatformMessageId - 1)) + 1;
    return id;
  }

  void _onBytes(List<int> bytes) {
    _decoder.add(bytes);
    for (final xml in _decoder.takeFrames()) {
      try {
        final envelope = CuppsXml.parseEnvelope(xml);
        logger(
          CuppsLogLevel.debug,
          scope,
          '$name message received.',
          direction: CuppsMessageDirection.inbound,
          deviceId: deviceId,
          messageId: envelope.messageId,
          xml: xml,
        );

        final completer = _pending.remove(envelope.messageId);
        if (completer != null) {
          completer.complete(xml);
        } else {
          Future.sync(() => onUnmatchedMessage(envelope)).ignore();
        }
      } catch (error, stackTrace) {
        logger(
          CuppsLogLevel.error,
          CuppsLogScope.protocol,
          '$name failed to parse inbound XML.',
          direction: CuppsMessageDirection.inbound,
          deviceId: deviceId,
          error: error,
          stackTrace: stackTrace,
          data: {'bufferedBytes': _decoder.bufferedBytes},
        );
      }
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    logger(
      CuppsLogLevel.error,
      CuppsLogScope.socket,
      '$name socket error.',
      deviceId: deviceId,
      error: error,
      stackTrace: stackTrace,
    );
    _failPending(error);
    onClosed();
  }

  void _onDone() {
    logger(
      CuppsLogLevel.warning,
      CuppsLogScope.socket,
      '$name socket closed.',
      deviceId: deviceId,
    );
    _failPending(CuppsRequestFailure('$name socket closed.'));
    onClosed();
  }

  void _failPending(Object error) {
    final pending = Map<int, Completer<String>>.of(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }
}
