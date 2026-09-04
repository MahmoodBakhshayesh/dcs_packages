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
  final _sessionFaultRestartCounts = <String, int>{};
  final _restartingDevices = <String>{};
  /// Devices that should stay locked until unlock / release / disconnect.
  final _persistentLockDeviceIds = <String>{};
  final _relockInFlight = <String>{};

  _CuppsSocketSession? _platformSession;
  CuppsApplicationInfo? _application;
  String? _eventToken;
  String? _applicationToken;
  String? _deviceToken;
  Timer? _heartbeatTimer;
  Timer? _lockRenewTimer;
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
    _startLockRenew();
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
        // Offline / power-off devices reject lock as illogicalMessage (MessageName).
        if (CuppsHardwareStatus.isOffline(current?.hardwareStatusLabel)) {
          logger(
            CuppsLogLevel.info,
            CuppsLogScope.device,
            'Skipping lock for offline ${device.descriptor.name}.',
            deviceId: device.id,
            data: {'hardware': current?.hardwareStatusLabel},
          );
          return;
        }
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
        final current = _deviceStatuses[device.id];
        // Multi-step configure/print sequences own the status until they finish.
        // Do not flicker busy → initialized after every intermediate command.
        if (current?.configuring == true || current?.printing == true) {
          updateDeviceStatus(
            device,
            busyState,
            busyMessage ?? 'Device request completed.',
            clearError: true,
          );
        } else {
          updateDeviceStatus(
            device,
            CuppsDeviceState.initialized,
            'Device request completed.',
            initialized: true,
            clearError: true,
          );
        }
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
  void setPersistentLockDesired(String deviceId, bool desired) {
    if (desired) {
      _persistentLockDeviceIds.add(deviceId);
    } else {
      _persistentLockDeviceIds.remove(deviceId);
      _relockInFlight.remove(deviceId);
    }
  }

  /// Show lines on the first acquired BG / DD device (boarding gate display).
  Future<CuppsCommandResult?> displayMessage(
    List<String> lines, {
    bool clearFirst = true,
  }) async {
    CuppsDevice? device;
    for (final candidate in _devices.values) {
      if (!candidate.supportsDisplay) continue;
      if (_deviceStatuses[candidate.id]?.acquired != true) continue;
      device = candidate;
      break;
    }
    if (device == null) return null;
    return device.displayLines(lines, clearFirst: clearFirst);
  }

  void _startLockRenew() {
    _lockRenewTimer?.cancel();
    _lockRenewTimer = Timer.periodic(_options.lockRenewInterval, (_) {
      unawaited(_renewPersistentLocks());
    });
  }

  Future<void> _renewPersistentLocks() async {
    if (_persistentLockDeviceIds.isEmpty) return;
    final ids = List<String>.from(_persistentLockDeviceIds);
    for (final id in ids) {
      final device = _devices[id];
      if (device == null || !device.supportsDeviceLock) continue;
      final status = _deviceStatuses[id];
      if (status?.acquired != true) continue;
      try {
        await device.lock(renew: status?.locked == true);
      } catch (error, stackTrace) {
        logger(
          CuppsLogLevel.warning,
          CuppsLogScope.device,
          'Persistent lock renew failed for ${device.descriptor.name}.',
          deviceId: id,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _relockIfDesired(CuppsDevice device) async {
    final id = device.id;
    if (!_persistentLockDeviceIds.contains(id)) return;
    if (!device.supportsDeviceLock) return;
    if (_relockInFlight.contains(id)) return;
    final current = _deviceStatuses[id];
    if (CuppsHardwareStatus.isOffline(current?.hardwareStatusLabel)) {
      return;
    }
    _relockInFlight.add(id);
    try {
      await device.lock(renew: false);
    } catch (error, stackTrace) {
      logger(
        CuppsLogLevel.warning,
        CuppsLogScope.device,
        'Auto re-lock failed for ${device.descriptor.name}.',
        deviceId: id,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _relockInFlight.remove(id);
    }
  }

  void _emitScan(CuppsDeviceDescriptor device, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_scanEventsController.isClosed) return;
    _scanEventsController.add(
      CuppsScanEvent(
        deviceId: device.id,
        deviceType: device.type,
        text: trimmed,
      ),
    );
  }

  /// Unmatched AEA → scan only for readers; never for BP/BT/BG printers or HDC status.
  static bool _shouldEmitUnmatchedAeaAsScan(
    CuppsDeviceDescriptor device,
    String text,
  ) {
    switch (device.type) {
      case CuppsDeviceType.barcodeReader:
      case CuppsDeviceType.boardingGateReader:
      case CuppsDeviceType.passportReader:
      case CuppsDeviceType.opticalCardReader:
      case CuppsDeviceType.biometricReader:
        break;
      case CuppsDeviceType.boardingPassPrinter:
      case CuppsDeviceType.bagTagPrinter:
      case CuppsDeviceType.documentPrinter:
      case CuppsDeviceType.displayDevice:
      case CuppsDeviceType.zlDevice:
      case CuppsDeviceType.ziDevice:
      case CuppsDeviceType.unknown:
        return false;
    }
    return !CuppsXml.looksLikePrinterOrStatusAea(text);
  }

  Future<void> _pullReaderData(CuppsDevice device) async {
    if (!device.supportsBarcodeRead) return;
    try {
      final result = await device.readWaitingData();
      for (final text in CuppsXml.bcDataTexts(result.rawXml)) {
        _emitScan(device.descriptor, text);
      }
    } catch (error, stackTrace) {
      logger(
        CuppsLogLevel.debug,
        CuppsLogScope.device,
        'readerRead failed for ${device.descriptor.name}.',
        deviceId: device.id,
        error: error,
        stackTrace: stackTrace,
      );
    }
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

  /// Unlock every device we hold without releasing or disconnecting.
  /// Used when the app minimizes so other apps can use the hardware.
  Future<void> unlockAllDevices() async {
    _persistentLockDeviceIds.clear();
    for (final device in _devices.values) {
      final current = _deviceStatuses[device.id];
      if (current?.locked != true) continue;
      try {
        await device.unlock();
      } catch (error, stackTrace) {
        logger(
          CuppsLogLevel.warning,
          CuppsLogScope.device,
          'Failed to unlock ${device.descriptor.name} during unlock-all.',
          deviceId: device.id,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lockRenewTimer?.cancel();
    _lockRenewTimer = null;
    _persistentLockDeviceIds.clear();
    _relockInFlight.clear();
    for (final timer in _sessionFaultRestartTimers.values) {
      timer.cancel();
    }
    _sessionFaultRestartTimers.clear();
    _sessionFaultRestartCounts.clear();
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

      final notifyEvent = CuppsXml.notifyEventNameFromXml(message.rawXml) ?? '';
      final cuppsDevice = _devices[device.id];

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

      // Platform lock TTL (~60s): clear flag and re-lock if we want persistence.
      if (notifyEvent == 'deviceLockExpiredEvent') {
        updateDeviceStatus(
          device,
          CuppsDeviceState.initialized,
          'Device lock expired — renewing.',
          locked: false,
          clearError: true,
        );
        if (cuppsDevice != null) {
          unawaited(_relockIfDesired(cuppsDevice));
        }
        return;
      }

      // Scan arrived while unlocked — data already discarded by platform.
      if (notifyEvent == 'dataAvailableNoLockerEvent') {
        updateDeviceStatus(
          device,
          CuppsDeviceState.dataAvailable,
          'Scan discarded (device not locked) — re-locking.',
          locked: false,
          clearError: true,
        );
        if (cuppsDevice != null) {
          unawaited(_relockIfDesired(cuppsDevice));
        }
        return;
      }

      final barcodes = CuppsXml.bcDataTexts(message.rawXml);
      if (barcodes.isNotEmpty) {
        for (final text in barcodes) {
          _emitScan(device, text);
        }
        updateDeviceStatus(
          device,
          CuppsDeviceState.dataAvailable,
          'Barcode data received.',
          clearError: true,
        );
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

      // Locked reader with data-available notify but no embedded bcData → pull.
      final locked = _deviceStatuses[device.id]?.locked == true;
      if (locked && cuppsDevice != null && cuppsDevice.supportsBarcodeRead) {
        unawaited(_pullReaderData(cuppsDevice));
      }
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
    final ready = label.toLowerCase() == 'ready' || CuppsHardwareStatus.isReady(label);
    final holdLock = current?.locked == true;

    if (CuppsHardwareStatus.isOffline(label)) {
      updateDeviceStatus(
        device,
        CuppsDeviceState.disconnected,
        'Status: $label',
        acquired: false,
        initialized: false,
        locked: false,
        hardwareStatusLabel: label,
        error: label,
        clearError: false,
      );
      _cancelSessionFaultRestart(device.id);
      return;
    }

    if (current?.configuring == true || current?.printing == true) {
      updateDeviceStatus(
        device,
        current!.state,
        'Status: $label',
        hardwareStatusLabel: label,
        locked: holdLock ? true : null,
        clearError: true,
      );
      return;
    }

    // Paper out / lid open / jam are hardware conditions — keep label for icons
    // but do not stash them as lastError (that painted a generic red ERR).
    updateDeviceStatus(
      device,
      ready ? CuppsDeviceState.initialized : CuppsDeviceState.degraded,
      'Status: $label',
      initialized: ready || holdLock,
      locked: holdLock ? true : null,
      hardwareStatusLabel: label,
      clearError: true,
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
    final previousHw = _deviceStatuses[device.id]?.hardwareStatusLabel;

    session?.abortPending(failure);
    await closeDeviceSession(device.id, notifyClosed: false);

    final offline = CuppsHardwareStatus.isOffline(previousHw);
    updateDeviceStatus(
      device,
      offline ? CuppsDeviceState.disconnected : CuppsDeviceState.degraded,
      offline
          ? 'Device offline (power off) — not restarting.'
          : 'CUPPS session fault: $description',
      locked: false,
      acquired: false,
      initialized: false,
      hardwareStatusLabel: previousHw,
      error: offline ? previousHw : description,
      clearError: false,
      clearHardwareStatus: previousHw == null,
    );

    logger(
      CuppsLogLevel.warning,
      CuppsLogScope.device,
      'Device ${device.name} session fault: $description',
      direction: CuppsMessageDirection.inbound,
      deviceId: device.id,
      messageId: message.messageId,
      xml: message.rawXml,
      data: {
        ...CuppsXml.messageLogData(message),
        if (previousHw != null) 'hardware': previousHw,
      },
    );

    if (offline) {
      _cancelSessionFaultRestart(device.id);
      return;
    }
    _scheduleSessionFaultRestart(device.id);
  }

  void _cancelSessionFaultRestart(String deviceId) {
    _sessionFaultRestartTimers.remove(deviceId)?.cancel();
  }

  void _scheduleSessionFaultRestart(String deviceId) {
    if (!_options.autoRestartOnSessionFault) return;
    if (_deviceToken == null || _application == null) return;
    if (_restartingDevices.contains(deviceId)) return;

    final current = _deviceStatuses[deviceId];
    if (CuppsHardwareStatus.isOffline(current?.hardwareStatusLabel)) {
      logger(
        CuppsLogLevel.info,
        CuppsLogScope.device,
        'Skipping auto-restart for offline/power-off device $deviceId.',
        deviceId: deviceId,
        data: {'hardware': current?.hardwareStatusLabel},
      );
      return;
    }

    final attempts = _sessionFaultRestartCounts[deviceId] ?? 0;
    if (attempts >= _options.maxSessionFaultRestarts) {
      logger(
        CuppsLogLevel.warning,
        CuppsLogScope.device,
        'Auto-restart limit reached for $deviceId '
        '(${_options.maxSessionFaultRestarts}); leaving device disconnected.',
        deviceId: deviceId,
      );
      updateDeviceStatus(
        current?.device ?? _devices[deviceId]!.descriptor,
        CuppsDeviceState.disconnected,
        'Auto-restart stopped after repeated session faults.',
        acquired: false,
        initialized: false,
        locked: false,
        error: current?.lastError,
      );
      return;
    }

    _cancelSessionFaultRestart(deviceId);
    _sessionFaultRestartTimers[deviceId] = Timer(
      _options.sessionFaultRestartDelay,
      () async {
        _sessionFaultRestartTimers.remove(deviceId);
        final device = _devices[deviceId];
        if (device == null) return;
        if (_platformStatus.state != CuppsPlatformState.ready &&
            _platformStatus.state != CuppsPlatformState.discoveringDevices) {
          return;
        }
        final before = _deviceStatuses[deviceId];
        if (CuppsHardwareStatus.isOffline(before?.hardwareStatusLabel)) {
          return;
        }
        _sessionFaultRestartCounts[deviceId] = attempts + 1;
        final result = await restartDevice(
          deviceId,
          deviceToken: _deviceToken!,
          airlineId: _application!.airlineCode,
        );
        if (result.ok) {
          _sessionFaultRestartCounts.remove(deviceId);
        } else if (CuppsHardwareStatus.isOffline(
              _deviceStatuses[deviceId]?.hardwareStatusLabel) ||
            result.result == 'powerOff') {
          _cancelSessionFaultRestart(deviceId);
          logger(
            CuppsLogLevel.info,
            CuppsLogScope.device,
            'Device $deviceId still offline after restart — not retrying.',
            deviceId: deviceId,
          );
        }
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
      // Printers spontaneously send HDC* / PTOK status AEA — never treat as barcode.
      // Only reader-class devices may surface unmatched AEA as a scan (e.g. BG).
      if (_shouldEmitUnmatchedAeaAsScan(device, text)) {
        _emitScan(device, text);
        logger(
          CuppsLogLevel.debug,
          CuppsLogScope.device,
          'Inbound AEA with no pending waiter (scan): $text',
          deviceId: device.id,
        );
      } else {
        logger(
          CuppsLogLevel.debug,
          CuppsLogScope.device,
          'Ignoring unmatched AEA (not a scan): $text',
          deviceId: device.id,
        );
      }
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
      // IATA AEA uses PROK; HDC/BOCA-style printers often reply HDCPTOK… / PTOK.
      // HDCERR… / PRERR / PTERR are hard failures — never treat as OK.
      final hasHardError = upper.contains('PRERR') ||
          upper.contains('PTERR') ||
          upper.contains('HDCERR') ||
          (upper.contains('ERR') && !upper.contains('PTOK') && !upper.contains('PROK'));
      final printOk = !hasHardError &&
          (upper.contains('PROK') || upper.contains('PTOK'));
      if (printOk) {
        matchedKind = CuppsAeaWaitKind.print;
        outcome = CuppsCommandResult(
          ok: true,
          result: 'ok',
          rawXml: message.rawXml,
          message: 'Print OK',
          aeaText: text,
        );
      } else if (hasHardError) {
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
      ok: _isOkCuppsResult(result),
      result: result,
      rawXml: xml,
      message: result.isEmpty ? null : result,
    );
  }

  /// CUPPS success codes include bare `OK` and qualified `OK-deviceAlreadyLocked`.
  static bool _isOkCuppsResult(String result) {
    final normalized = result.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'ok') return true;
    return normalized.startsWith('ok-') || normalized.startsWith('ok_');
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

  /// Serializes all outbound frames (requests + aeaResponse) on this socket.
  /// Concurrent writes interleaved bytes / burned message IDs and triggered
  /// platform `messageIDSequenceError` (e.g. app sent 20 then 22).
  Future<void> _outboundTail = Future<void>.value();

  bool get isOpen => !_closed && transport.isOpen;

  Future<T> _withOutboundLock<T>(Future<T> Function() action) {
    final operation = _outboundTail.catchError((_) {}).then((_) => action());
    _outboundTail = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> connect(
    CuppsEndpoint endpoint, {
    required Duration timeout,
  }) async {
    _closed = false;
    _outboundTail = Future<void>.value();
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

    late final int messageId;
    late final Completer<String> completer;

    // Allocate ID + write under one lock so concurrent respond()/request()
    // cannot skip an ID the platform never receives.
    await _withOutboundLock(() async {
      if (!isOpen) {
        throw CuppsRequestFailure('$name socket is not connected.');
      }

      messageId = _messageId;
      final xml = buildXml(messageId);
      completer = Completer<String>();
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

      try {
        await transport.write(_codec.encode(xml));
        // Advance only after a successful write so failed sends do not create gaps.
        _messageId = (_messageId % (minPlatformMessageId - 1)) + 1;
      } catch (error) {
        _pending.remove(messageId);
        rethrow;
      }
    });

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(messageId);
        throw CuppsRequestFailure('$name request $messageId timed out.');
      },
    );
  }

  Future<void> respond(String xml) async {
    await _withOutboundLock(() async {
      if (!isOpen) {
        throw CuppsRequestFailure('$name socket is not connected.');
      }
      logger(
        CuppsLogLevel.debug,
        scope,
        '$name response sent.',
        direction: CuppsMessageDirection.outbound,
        deviceId: deviceId,
        xml: xml,
      );
      await transport.write(_codec.encode(xml));
    });
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
