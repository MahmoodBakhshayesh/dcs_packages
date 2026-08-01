// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'cupps_configure.dart';
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
  final _scanEventsController = StreamController<CuppsScanEvent>.broadcast();
  final _devices = <String, CuppsDevice>{};
  final _deviceStatuses = <String, CuppsDeviceStatus>{};
  final _deviceSessions = <String, _CuppsSocketSession>{};
  final _aeaWaits = <String, Map<CuppsAeaWaitKind, Completer<CuppsCommandResult>>>{};
  final _sessionFaultRestartTimers = <String, Timer>{};
  final _restartingDevices = <String>{};

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

  /// Unsolicited barcode / OCR / reader payloads (MRZ, boarding pass, etc.).
  Stream<CuppsScanEvent> get scanEvents => _scanEventsController.stream;

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
      final endpoint = _deviceConnectionEndpoint(descriptor);
      updateDeviceStatus(
        descriptor,
        CuppsDeviceState.discovered,
        'Device discovered at $endpoint.',
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

    await Future.wait(
      _devices.values.map((device) => _connectDevice(device.descriptor)),
    );

    _setPlatformStatus(
      CuppsPlatformState.ready,
      'CUPPS platform and devices are ready.',
      clearError: true,
    );
    _startHeartbeat();
  }

  /// Acquire, set interface mode, and refresh status for every connected device.
  Future<void> initializeDevices({
    required String deviceToken,
    required String airlineId,
  }) async {
    await Future.wait(
      _devices.values.map((device) async {
        try {
          await device.initialize(
            deviceToken: deviceToken,
            airlineId: airlineId,
          );
        } catch (error, stackTrace) {
          logger(
            CuppsLogLevel.warning,
            CuppsLogScope.device,
            'Device ${device.descriptor.name} initialization failed.',
            deviceId: device.id,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );

    await Future.wait(
      _devices.values.map((device) async {
        if (!device.supportsDeviceLock) return;
        final current = _deviceStatuses[device.id];
        if (current?.acquired != true) return;
        try {
          await device.lock();
        } catch (error, stackTrace) {
          logger(
            CuppsLogLevel.warning,
            CuppsLogScope.device,
            'Device ${device.descriptor.name} lock failed after init.',
            deviceId: device.id,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
  }

  /// Send AEA configure commands to acquired BP/BT/BG devices.
  Future<void> configureDevices({
    required CuppsConfigurePlan plan,
    bool tolerateMissingDeviceAck = true,
    bool waitForReady = false,
    Duration readyTimeout = const Duration(seconds: 5),
  }) async {
    if (plan.isEmpty) return;

    await Future.wait(
      _devices.values.map((device) async {
        final commands = plan.commandsFor(device.type);
        if (commands.isEmpty) return;

        final current = _deviceStatuses[device.id];
        if (current?.acquired != true) {
          logger(
            CuppsLogLevel.warning,
            CuppsLogScope.device,
            'Skipping configure for ${device.descriptor.name}; device not acquired.',
            deviceId: device.id,
          );
          return;
        }

        try {
          final result = await device.completeConfigure(
            commands,
            tolerateMissingDeviceAck: tolerateMissingDeviceAck,
          );
          if (!result.ok) {
            logger(
              CuppsLogLevel.warning,
              CuppsLogScope.device,
              'Configure failed for ${device.descriptor.name}: ${result.message}',
              deviceId: device.id,
            );
            return;
          }

          if (!waitForReady) return;

          if (device.type == CuppsDeviceType.boardingPassPrinter ||
              device.type == CuppsDeviceType.bagTagPrinter) {
            final ready = await device.waitForHardwareStatus(
              'ready',
              timeout: readyTimeout,
            );
            logger(
              ready ? CuppsLogLevel.info : CuppsLogLevel.warning,
              CuppsLogScope.device,
              ready
                  ? '${device.descriptor.name} reported ready after configure.'
                  : '${device.descriptor.name} did not report ready after configure.',
              deviceId: device.id,
              data: {'hardware': device.status?.hardwareStatusLabel},
            );
          }
        } catch (error, stackTrace) {
          logger(
            CuppsLogLevel.warning,
            CuppsLogScope.device,
            'Configure exception for ${device.descriptor.name}.',
            deviceId: device.id,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
  }

  @override
  void registerInboundAeaWait(String deviceId, CuppsAeaWaitKind kind) {
    final waits = _aeaWaits.putIfAbsent(deviceId, () => {});
    waits.remove(kind)?.complete(
      const CuppsCommandResult(
        ok: false,
        result: 'superseded',
        rawXml: '',
        message: 'Superseded by a newer AEA wait.',
      ),
    );
    waits[kind] = Completer<CuppsCommandResult>();
  }

  @override
  void cancelInboundAeaWait(String deviceId, CuppsAeaWaitKind kind) {
    final waits = _aeaWaits[deviceId];
    waits?.remove(kind);
    if (waits != null && waits.isEmpty) {
      _aeaWaits.remove(deviceId);
    }
  }

  @override
  Future<CuppsCommandResult> waitForInboundAea(
    String deviceId,
    CuppsAeaWaitKind kind, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final completer = _aeaWaits[deviceId]?[kind];
    if (completer == null) {
      throw CuppsRequestFailure('No inbound AEA wait registered for $deviceId ($kind).');
    }
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      cancelInboundAeaWait(deviceId, kind);
      return const CuppsCommandResult(
        ok: false,
        result: 'timeout',
        rawXml: '',
        message: 'Timed out waiting for device AEA acknowledgement.',
      );
    }
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

  /// Close the device socket and reset session flags.
  @override
  Future<void> closeDeviceSession(
    String deviceId, {
    bool notifyClosed = true,
  }) async {
    _cancelSessionFaultRestart(deviceId);
    final device = _devices[deviceId]?.descriptor;
    if (device == null) return;

    final session = _deviceSessions.remove(deviceId);
    _aeaWaits.remove(deviceId);
    await session?.close(notify: notifyClosed);

    if (!notifyClosed) {
      updateDeviceStatus(
        device,
        CuppsDeviceState.disconnected,
        'Device socket closed.',
        locked: false,
        acquired: false,
        initialized: false,
        clearError: true,
        clearHardwareStatus: true,
      );
    }
  }

  /// Release, close, reconnect, and re-initialize one device (artemis restart parity).
  @override
  Future<CuppsCommandResult> restartDevice(
    String deviceId, {
    required String deviceToken,
    required String airlineId,
    bool relock = true,
    List<String> configureCommands = const [],
  }) async {
    final cuppsDevice = _devices[deviceId];
    if (cuppsDevice == null) {
      return const CuppsCommandResult(
        ok: false,
        result: 'unknownDevice',
        rawXml: '',
        message: 'Device is not registered on this client.',
      );
    }

    if (_restartingDevices.contains(deviceId)) {
      return const CuppsCommandResult(
        ok: false,
        result: 'busy',
        rawXml: '',
        message: 'Device restart is already in progress.',
      );
    }

    final current = _deviceStatuses[deviceId];
    if (current?.printing == true || current?.configuring == true) {
      return const CuppsCommandResult(
        ok: false,
        result: 'busy',
        rawXml: '',
        message: 'Cannot restart while the device is printing or configuring.',
      );
    }

    _restartingDevices.add(deviceId);
    _cancelSessionFaultRestart(deviceId);

    try {
      updateDeviceStatus(
        cuppsDevice.descriptor,
        CuppsDeviceState.busy,
        'Restarting device session.',
        clearError: true,
      );

      await cuppsDevice.release(closeSocket: true);

      await _connectDevice(cuppsDevice.descriptor);
      final init = await cuppsDevice.initialize(
        deviceToken: deviceToken,
        airlineId: airlineId,
        forceAcquire: true,
      );
      if (!init.ok) {
        updateDeviceStatus(
          cuppsDevice.descriptor,
          CuppsDeviceState.failed,
          init.message ?? 'Device restart failed during initialize.',
          error: init.message,
        );
        return init;
      }

      if (relock && cuppsDevice.supportsDeviceLock) {
        final lockResult = await cuppsDevice.lock();
        if (!lockResult.ok) {
          logger(
            CuppsLogLevel.warning,
            CuppsLogScope.device,
            'Device ${cuppsDevice.descriptor.name} lock failed after restart.',
            deviceId: deviceId,
            data: {'result': lockResult.result},
          );
        }
      }

      if (configureCommands.isNotEmpty) {
        final configureResult = await cuppsDevice.completeConfigure(configureCommands);
        if (!configureResult.ok) {
          return configureResult;
        }
      }

      updateDeviceStatus(
        cuppsDevice.descriptor,
        CuppsDeviceState.initialized,
        'Device session restarted.',
        acquired: true,
        initialized: true,
        clearError: true,
      );

      return CuppsCommandResult(
        ok: true,
        result: 'ok',
        rawXml: '',
        message: 'Device session restarted.',
      );
    } catch (error) {
      updateDeviceStatus(
        cuppsDevice.descriptor,
        CuppsDeviceState.failed,
        'Device restart failed.',
        error: error,
      );
      return CuppsCommandResult(
        ok: false,
        result: 'restartFailed',
        rawXml: '',
        message: error.toString(),
      );
    } finally {
      _restartingDevices.remove(deviceId);
    }
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
      final current = _deviceStatuses[device.id];
      if (current?.acquired == true) {
        await _restoreDeviceSession(device);
        session = _deviceSessions[device.id];
      } else {
        throw CuppsRequestFailure(
          'Device ${device.name} is not connected. Connect platform first.',
        );
      }
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
      final responseEnvelope = CuppsXml.parseEnvelope(xml);
      logger(
        CuppsLogLevel.debug,
        CuppsLogScope.device,
        'Device ${device.name} response: ${CuppsXml.messageLogSummary(responseEnvelope)}',
        direction: CuppsMessageDirection.inbound,
        deviceId: device.id,
        messageId: responseEnvelope.messageId,
        xml: xml,
        data: CuppsXml.messageLogData(responseEnvelope),
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
    bool? configuring,
    bool? printing,
    String? hardwareStatusLabel,
    Object? error,
    bool clearError = false,
    bool clearHardwareStatus = false,
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
            configuring: configuring ?? false,
            printing: printing ?? false,
            hardwareStatusLabel: hardwareStatusLabel,
            lastChangedAt: DateTime.now(),
            lastError: clearError ? null : error,
          )
        : previous.copyWith(
            state: state,
            message: message,
            locked: locked,
            acquired: acquired,
            initialized: initialized,
            configuring: configuring,
            printing: printing,
            hardwareStatusLabel: hardwareStatusLabel,
            lastChangedAt: DateTime.now(),
            lastError: error,
            clearError: clearError,
            clearHardwareStatus: clearHardwareStatus,
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
      data: {
        'state': state.name,
        'deviceName': device.name,
        if (hardwareStatusLabel != null) 'hardwareStatus': hardwareStatusLabel,
        if (locked == true || status.locked) 'locked': true,
        if (acquired == true || status.acquired) 'acquired': true,
        if (initialized == true || status.initialized) 'initialized': true,
        if (configuring == true || status.configuring) 'configuring': true,
        if (printing == true || status.printing) 'printing': true,
      },
    );
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final timer in _sessionFaultRestartTimers.values) {
      timer.cancel();
    }
    _sessionFaultRestartTimers.clear();
    _restartingDevices.clear();

    _setPlatformStatus(
      CuppsPlatformState.disconnecting,
      'Disconnecting CUPPS platform and devices.',
    );

    for (final device in _devices.values) {
      final current = _deviceStatuses[device.id];
      if (current?.acquired != true) {
        await closeDeviceSession(device.id, notifyClosed: false);
        continue;
      }
      try {
        await device.release(closeSocket: true);
      } catch (error, stackTrace) {
        logger(
          CuppsLogLevel.warning,
          CuppsLogScope.device,
          'Failed to release ${device.descriptor.name} during disconnect.',
          deviceId: device.id,
          error: error,
          stackTrace: stackTrace,
        );
        await closeDeviceSession(device.id, notifyClosed: false);
      }
    }

    _deviceSessions.clear();
    _aeaWaits.clear();
    await _platformSession?.close(notify: false);
    _platformSession = null;

    for (final status in _deviceStatuses.values.toList()) {
      updateDeviceStatus(
        status.device,
        CuppsDeviceState.disconnected,
        'Device disconnected.',
        locked: false,
        acquired: false,
        initialized: false,
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
    await _scanEventsController.close();
    for (final controller in _deviceStatusControllers.values) {
      await controller.close();
    }
    await logger.close();
  }

  Future<void> _restoreDeviceSession(CuppsDeviceDescriptor device) async {
    final cuppsDevice = _devices[device.id];
    final token = _deviceToken;
    final airline = _application?.airlineCode;
    if (cuppsDevice == null || token == null || airline == null) {
      throw const CuppsRequestFailure(
        'Cannot restore device session before platform authentication.',
      );
    }

    final existing = _deviceSessions[device.id];
    final current = _deviceStatuses[device.id];
    if (existing != null &&
        existing.isOpen &&
        current?.acquired == true &&
        current?.initialized == true) {
      return;
    }

    if (existing != null) {
      await closeDeviceSession(device.id, notifyClosed: false);
    }

    await _connectDevice(device);
    final acquire = await cuppsDevice.acquire(
      deviceToken: token,
      airlineId: airline,
      force: true,
    );
    if (!acquire.ok) {
      throw CuppsRequestFailure(
        'Device ${device.name} re-acquire failed: ${acquire.result}',
      );
    }
    final mode = await cuppsDevice.interfaceMode();
    if (!mode.ok) {
      throw CuppsRequestFailure(
        'Device ${device.name} interface mode restore failed: ${mode.result}',
      );
    }
    await cuppsDevice.refreshStatus();
    if (cuppsDevice.supportsDeviceLock && current?.locked == true) {
      await cuppsDevice.lock();
    }
  }

  Future<void> _connectDevice(CuppsDeviceDescriptor device) async {
    final endpoint = _deviceConnectionEndpoint(device);
    if (endpoint.host.trim().isEmpty || endpoint.port <= 0) {
      throw CuppsRequestFailure(
        'Device ${device.name} has no valid connection endpoint (host/port).',
      );
    }

    final stale = _deviceSessions.remove(device.id);
    if (stale != null) {
      await stale.close(notify: false);
    }

    updateDeviceStatus(
      device,
      CuppsDeviceState.connecting,
      'Connecting to $endpoint.',
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
        _cancelSessionFaultRestart(device.id);
        updateDeviceStatus(
          device,
          CuppsDeviceState.disconnected,
          'Device socket closed.',
          locked: false,
          acquired: false,
          initialized: false,
          clearHardwareStatus: true,
        );
      },
    );

    try {
      await session.connect(endpoint, timeout: _options.connectTimeout);
      await _negotiateDeviceInterface(session, device);
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

  CuppsEndpoint _deviceConnectionEndpoint(CuppsDeviceDescriptor device) {
    final platformEndpoint = _platformStatus.endpoint;
    if (platformEndpoint == null) {
      return device.endpoint;
    }
    return device.connectionEndpoint(platformEndpoint);
  }

  Future<void> _negotiateDeviceInterface(
    _CuppsSocketSession session,
    CuppsDeviceDescriptor device,
  ) async {
    final levelsXml = await session.request(
      (messageId) => CuppsXml.interfaceLevelsAvailableRequest(
        messageId: messageId,
        hsXsdVersion: _options.hsXsdVersion,
      ),
      _options.requestTimeout,
    );
    final levels = CuppsXml.interfaceLevels(levelsXml);
    final level = levels.contains(_options.interfaceLevel)
        ? _options.interfaceLevel
        : (levels.isNotEmpty ? levels.first : null);
    if (level == null) {
      throw CuppsRequestFailure(
        'Device ${device.name} has no available interface levels.',
      );
    }

    final selectedLevelXml = await session.request(
      (messageId) => CuppsXml.interfaceLevelRequest(
        messageId: messageId,
        level: level,
      ),
      _options.requestTimeout,
    );
    final selected = _resultFromXml(selectedLevelXml);
    if (!selected.ok) {
      throw CuppsRequestFailure(
        'Device ${device.name} interface level selection failed: ${selected.result}',
      );
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
      _applyStatusFromNotify(message.rawXml);
      logger(
        CuppsLogLevel.info,
        CuppsLogScope.platform,
        'Platform notify: ${CuppsXml.messageLogSummary(message)}',
        direction: CuppsMessageDirection.inbound,
        messageId: message.messageId,
        xml: message.rawXml,
        data: CuppsXml.messageLogData(message),
      );
      return;
    }
  }

  Future<void> _handleDeviceMessage(
    CuppsDeviceDescriptor device,
    CuppsEnvelope message,
  ) async {
    if (message.messageName == 'aeaRequest') {
      logger(
        CuppsLogLevel.info,
        CuppsLogScope.device,
        'Device ${device.name} inbound AEA: ${CuppsXml.messageLogSummary(message)}',
        direction: CuppsMessageDirection.inbound,
        deviceId: device.id,
        messageId: message.messageId,
        xml: message.rawXml,
        data: CuppsXml.messageLogData(message),
      );
      await _handleInboundAeaRequest(device, message);
      return;
    }

    if (message.messageName == 'notify') {
      if (CuppsXml.isSessionFaultNotify(message)) {
        await _handleDeviceSessionFault(device, message);
        return;
      }

      final hardware = CuppsXml.hardwareStatusLabelFromNotify(message.rawXml);
      _applyStatusFromNotify(message.rawXml);
      updateDeviceStatus(
        device,
        CuppsDeviceState.dataAvailable,
        'Device notify: ${CuppsXml.messageLogSummary(message)}',
        hardwareStatusLabel: hardware,
        clearError: true,
      );
      logger(
        CuppsLogLevel.info,
        CuppsLogScope.device,
        'Device ${device.name} notify: ${CuppsXml.messageLogSummary(message)}',
        direction: CuppsMessageDirection.inbound,
        deviceId: device.id,
        messageId: message.messageId,
        xml: message.rawXml,
        data: CuppsXml.messageLogData(message),
      );
      return;
    }

    logger(
      CuppsLogLevel.info,
      CuppsLogScope.device,
      'Device ${device.name} inbound: ${CuppsXml.messageLogSummary(message)}',
      direction: CuppsMessageDirection.inbound,
      deviceId: device.id,
      messageId: message.messageId,
      xml: message.rawXml,
      data: CuppsXml.messageLogData(message),
    );
  }

  void _applyStatusFromNotify(String rawXml) {
    final deviceName = CuppsXml.deviceNameFromNotify(rawXml);
    if (deviceName == null) return;

    final device = _devices.values
        .where((entry) => entry.descriptor.name == deviceName)
        .map((entry) => entry.descriptor)
        .firstOrNull;
    if (device == null) return;

    final label = CuppsXml.hardwareStatusLabelFromNotify(rawXml);
    if (label == null) return;

    final current = _deviceStatuses[device.id];
    final ready = label.toLowerCase() == 'ready';

    if (current?.configuring == true || current?.printing == true) {
      updateDeviceStatus(
        device,
        current!.state,
        'Status: $label',
        hardwareStatusLabel: label,
        clearError: ready,
        error: ready ? null : label,
      );
      return;
    }

    updateDeviceStatus(
      device,
      ready ? CuppsDeviceState.initialized : CuppsDeviceState.degraded,
      'Status: $label',
      initialized: true,
      hardwareStatusLabel: label,
      clearError: ready,
      error: ready ? null : label,
    );
  }

  Future<void> _handleDeviceSessionFault(
    CuppsDeviceDescriptor device,
    CuppsEnvelope message,
  ) async {
    final description =
        CuppsXml.sessionFaultDescription(message) ?? 'session fault';
    final session = _deviceSessions[device.id];
    final failure = CuppsRequestFailure('CUPPS session fault: $description');

    session?.abortPending(failure);
    await closeDeviceSession(device.id, notifyClosed: false);

    updateDeviceStatus(
      device,
      CuppsDeviceState.degraded,
      'CUPPS session fault: $description',
      locked: false,
      acquired: false,
      initialized: false,
      error: description,
      clearHardwareStatus: true,
    );

    logger(
      CuppsLogLevel.warning,
      CuppsLogScope.device,
      'Device ${device.name} session fault: $description',
      direction: CuppsMessageDirection.inbound,
      deviceId: device.id,
      messageId: message.messageId,
      xml: message.rawXml,
      data: CuppsXml.messageLogData(message),
    );

    _scheduleSessionFaultRestart(device.id);
  }

  void _cancelSessionFaultRestart(String deviceId) {
    _sessionFaultRestartTimers.remove(deviceId)?.cancel();
  }

  void _scheduleSessionFaultRestart(String deviceId) {
    if (!_options.autoRestartOnSessionFault) return;
    if (_deviceToken == null || _application == null) return;
    if (_restartingDevices.contains(deviceId)) return;

    _cancelSessionFaultRestart(deviceId);
    _sessionFaultRestartTimers[deviceId] = Timer(
      _options.sessionFaultRestartDelay,
      () {
        _sessionFaultRestartTimers.remove(deviceId);
        final device = _devices[deviceId];
        if (device == null) return;
        if (_platformStatus.state != CuppsPlatformState.ready &&
            _platformStatus.state != CuppsPlatformState.discoveringDevices) {
          return;
        }
        restartDevice(
          deviceId,
          deviceToken: _deviceToken!,
          airlineId: _application!.airlineCode,
        ).ignore();
      },
    );
  }

  Future<void> _handleInboundAeaRequest(
    CuppsDeviceDescriptor device,
    CuppsEnvelope message,
  ) async {
    final session = _deviceSessions[device.id];
    if (session != null) {
      await session.respond(
        CuppsXml.aeaResponse(messageId: message.messageId),
      );
    }

    final texts = CuppsXml.aeaRequestTexts(message.rawXml);
    if (texts.isEmpty) return;
    final text = texts.join();
    final upper = text.toUpperCase();

    final waits = _aeaWaits[device.id];
    if (waits == null || waits.isEmpty) {
      if (!_scanEventsController.isClosed) {
        _scanEventsController.add(
          CuppsScanEvent(
            deviceId: device.id,
            deviceType: device.type,
            text: text,
          ),
        );
      }
      logger(
        CuppsLogLevel.debug,
        CuppsLogScope.device,
        'Inbound AEA with no pending waiter: $text',
        deviceId: device.id,
      );
      return;
    }

    CuppsAeaWaitKind? matchedKind;
    CuppsCommandResult? outcome;

    if (waits.containsKey(CuppsAeaWaitKind.configure)) {
      if (upper.contains('OK')) {
        matchedKind = CuppsAeaWaitKind.configure;
        outcome = CuppsCommandResult(
          ok: true,
          result: 'ok',
          rawXml: message.rawXml,
          message: 'Configuration OK',
          aeaText: text,
        );
      } else if (upper.contains('ERR')) {
        matchedKind = CuppsAeaWaitKind.configure;
        outcome = CuppsCommandResult(
          ok: false,
          result: 'error',
          rawXml: message.rawXml,
          message: text,
          aeaText: text,
        );
      }
    }

    if (matchedKind == null && waits.containsKey(CuppsAeaWaitKind.print)) {
      if (upper.contains('PROK') && !upper.contains('PRERR')) {
        matchedKind = CuppsAeaWaitKind.print;
        outcome = CuppsCommandResult(
          ok: true,
          result: 'ok',
          rawXml: message.rawXml,
          message: 'Print OK',
          aeaText: text,
        );
      } else if (upper.contains('ERR') || upper.contains('PRERR')) {
        matchedKind = CuppsAeaWaitKind.print;
        outcome = CuppsCommandResult(
          ok: false,
          result: 'error',
          rawXml: message.rawXml,
          message: text,
          aeaText: text,
        );
      }
    }

    if (matchedKind == null || outcome == null) return;

    final completer = waits.remove(matchedKind);
    if (waits.isEmpty) {
      _aeaWaits.remove(device.id);
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(outcome);
    }

    updateDeviceStatus(
      device,
      outcome.ok ? CuppsDeviceState.initialized : CuppsDeviceState.degraded,
      outcome.message ?? (outcome.ok ? 'AEA complete.' : 'AEA failed.'),
      configuring: matchedKind == CuppsAeaWaitKind.configure ? false : null,
      printing: matchedKind == CuppsAeaWaitKind.print ? false : null,
      clearError: outcome.ok,
      error: outcome.ok ? null : outcome.message,
    );
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
    final requestEnvelope = CuppsXml.parseEnvelope(xml);

    logger(
      CuppsLogLevel.debug,
      scope,
      '$name request: ${CuppsXml.messageLogSummary(requestEnvelope)}',
      direction: CuppsMessageDirection.outbound,
      deviceId: deviceId,
      messageId: messageId,
      xml: xml,
      data: CuppsXml.messageLogData(requestEnvelope),
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

  Future<void> close({bool notify = true}) async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await transport.close();
    _failPending(CuppsRequestFailure('$name socket closed.'));
    if (notify) {
      onClosed();
    }
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
          '$name inbound: ${CuppsXml.messageLogSummary(envelope)}',
          direction: CuppsMessageDirection.inbound,
          deviceId: deviceId,
          messageId: envelope.messageId,
          xml: xml,
          data: CuppsXml.messageLogData(envelope),
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

  void abortPending(CuppsRequestFailure failure) {
    _failPending(failure);
  }
}
