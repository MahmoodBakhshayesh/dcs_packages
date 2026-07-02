// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'dcs_adapters.dart';
import 'dcs_config_store.dart';
import 'dcs_models.dart';
import 'dcs_request_queue.dart';

/// Coordinates discovery, matching, connection, reconnect, health checks, and UI status.
class DcsDeviceController {
  DcsDeviceController({
    DcsDeviceConfig initialConfig = const DcsDeviceConfig(),
    List<DcsDeviceAdapter> adapters = const [DcsSerialPortAdapter()],
    DcsConfigStore? configStore,
    DcsRetryPolicy retryPolicy = const DcsRetryPolicy(),
    DcsConnectionHealthPolicy healthPolicy = const DcsConnectionHealthPolicy(),
    DcsLogger? logger,
  }) : _config = initialConfig,
       _adapters = adapters,
       _configStore = configStore,
       _retryPolicy = retryPolicy,
       _healthPolicy = healthPolicy,
       _logger = logger {
    _seedStatuses(initialConfig.profiles);
  }

  DcsDeviceConfig _config;
  final List<DcsDeviceAdapter> _adapters;
  final DcsConfigStore? _configStore;
  final DcsRetryPolicy _retryPolicy;
  final DcsConnectionHealthPolicy _healthPolicy;
  final DcsLogger? _logger;

  final _statusController =
      StreamController<Map<String, DcsDeviceStatus>>.broadcast();
  final _statuses = <String, DcsDeviceStatus>{};
  final _sessions = <String, DcsDeviceSession>{};
  final _requestQueues = <String, DcsDeviceRequestQueue>{};
  final _dataControllers = <String, StreamController<List<int>>>{};
  final _dataSubscriptions = <String, StreamSubscription<List<int>>>{};
  final _healthTimers = <String, Timer>{};
  final _missedHeartbeats = <String, int>{};
  final _lastDiscovery = <String, DcsDiscoveredDevice>{};
  final _connecting = <String>{};

  Timer? _monitorTimer;
  bool _closed = false;

  DcsDeviceConfig get config => _config;

  List<DcsDeviceProfile> get profiles => List.unmodifiable(_config.profiles);

  Map<String, DcsDeviceStatus> get currentStatuses =>
      Map.unmodifiable(_statuses);

  Stream<Map<String, DcsDeviceStatus>> get statuses => _statusController.stream;

  /// Loads saved config, emits initial statuses, discovers devices, and optionally connects.
  Future<void> start({bool connect = true}) async {
    _ensureOpen();

    final savedConfig = await _configStore?.load();
    if (savedConfig != null) {
      _config = savedConfig;
      _seedStatuses(savedConfig.profiles);
      _emitStatuses();
      _log(DcsLogLevel.info, 'Loaded saved DCS device configuration.');
    }

    await discover();

    if (connect) {
      await connectAll();
    }

    if (_config.autoReconnect) {
      startMonitoring();
    }
  }

  Future<void> saveConfig(DcsDeviceConfig config) async {
    _ensureOpen();
    _config = config;
    _seedStatuses(config.profiles);
    await _configStore?.save(config);
    _emitStatuses();
    _log(DcsLogLevel.info, 'Saved DCS device configuration.');
  }

  Future<void> upsertProfile(
    DcsDeviceProfile profile, {
    bool persist = true,
  }) async {
    final profiles = [..._config.profiles];
    final index = profiles.indexWhere((existing) => existing.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }

    await saveConfig(_config.copyWith(profiles: profiles));

    if (profile.enabled && persist) {
      await discover();
    }
  }

  Future<void> removeProfile(String profileId) async {
    await disconnect(profileId);
    _statuses.remove(profileId);
    _lastDiscovery.remove(profileId);
    await _dataControllers.remove(profileId)?.close();
    await saveConfig(
      _config.copyWith(
        profiles: _config.profiles
            .where((profile) => profile.id != profileId)
            .toList(),
      ),
    );
  }

  /// Discovers all devices supported by registered adapters and matches them to profiles.
  Future<List<DcsDiscoveredDevice>> discover() async {
    _ensureOpen();
    _log(DcsLogLevel.debug, 'Discovering DCS devices.');

    for (final profile in _config.profiles.where(
      (profile) => profile.enabled,
    )) {
      if (_sessions.containsKey(profile.id)) continue;
      _setStatus(
        profile.id,
        DcsDeviceConnectionState.discovering,
        message: 'Discovering...',
      );
    }

    final discoveries = <DcsDiscoveredDevice>[];
    for (final adapter in _adapters) {
      try {
        discoveries.addAll(await adapter.discover());
      } catch (error, stackTrace) {
        _log(
          DcsLogLevel.warning,
          'Device discovery failed for ${adapter.transport.name}.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    for (final profile in _config.profiles.where(
      (profile) => profile.enabled,
    )) {
      final match = _bestMatch(profile, discoveries);
      if (match == null) {
        if (!_sessions.containsKey(profile.id)) {
          _setStatus(
            profile.id,
            DcsDeviceConnectionState.disconnected,
            message: 'No matching ${profile.label} found.',
          );
        }
        continue;
      }

      _lastDiscovery[profile.id] = match;
      if (!_sessions.containsKey(profile.id)) {
        _setStatus(
          profile.id,
          DcsDeviceConnectionState.available,
          message: '${profile.label} found on ${match.portName}.',
          device: match,
          clearError: true,
        );
      }
    }

    _log(
      DcsLogLevel.info,
      'Discovered ${discoveries.length} device(s).',
      data: {'count': discoveries.length},
    );
    return List.unmodifiable(discoveries);
  }

  Future<void> connectAll() async {
    for (final profile in _config.profiles.where(
      (profile) => profile.enabled,
    )) {
      await connect(profile.id);
    }
  }

  Future<void> connect(String profileId) async {
    _ensureOpen();
    if (_sessions.containsKey(profileId) || _connecting.contains(profileId)) {
      return;
    }

    final profile = _profileById(profileId);
    if (profile == null || !profile.enabled) return;

    _connecting.add(profileId);
    try {
      await _connectWithRetry(profile);
    } finally {
      _connecting.remove(profileId);
    }
  }

  Future<void> reconnect(String profileId) async {
    await disconnect(profileId);
    await discover();
    await connect(profileId);
  }

  Future<void> disconnect(String profileId) async {
    _healthTimers.remove(profileId)?.cancel();
    _missedHeartbeats.remove(profileId);
    await _dataSubscriptions.remove(profileId)?.cancel();
    _requestQueues.remove(profileId);

    final session = _sessions.remove(profileId);
    if (session != null) {
      await session.close();
      _setStatus(
        profileId,
        DcsDeviceConnectionState.disconnected,
        message: 'Disconnected.',
      );
      _log(DcsLogLevel.info, 'Disconnected device.', profileId: profileId);
    }
  }

  Future<void> send(String profileId, List<int> bytes) async {
    final session = _sessions[profileId];
    if (session == null) {
      throw DcsDeviceConnectionException(
        'No active session for profile $profileId.',
      );
    }
    await session.write(bytes);
  }

  /// Sends a command and waits for the matching response in profile order.
  Future<DcsDeviceResponse> sendRequest(
    String profileId,
    List<int> bytes, {
    DcsDeviceRequestOptions options = const DcsDeviceRequestOptions(),
  }) async {
    return _requestQueueFor(
      profileId,
      options,
    ).sendBytes(bytes, options: options);
  }

  /// Sends encoded text and waits for a classified response.
  Future<DcsDeviceResponse> sendTextRequest(
    String profileId,
    String command, {
    DcsDeviceRequestOptions options = const DcsDeviceRequestOptions(),
  }) async {
    return _requestQueueFor(
      profileId,
      options,
    ).sendText(command, options: options);
  }

  Stream<List<int>> dataFor(String profileId) {
    return _dataControllerFor(profileId).stream;
  }

  void startMonitoring() {
    _ensureOpen();
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(_config.discoveryInterval, (_) {
      unawaited(_monitorOnce());
    });
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;

    stopMonitoring();
    for (final timer in _healthTimers.values) {
      timer.cancel();
    }
    _healthTimers.clear();

    for (final subscription in _dataSubscriptions.values) {
      await subscription.cancel();
    }
    _dataSubscriptions.clear();

    for (final session in _sessions.values) {
      await session.close();
    }
    _sessions.clear();
    _requestQueues.clear();

    for (final controller in _dataControllers.values) {
      await controller.close();
    }
    _dataControllers.clear();

    await _statusController.close();
  }

  Future<void> _monitorOnce() async {
    if (_closed) return;
    await discover();
    for (final profile in _config.profiles.where(
      (profile) => profile.enabled,
    )) {
      final status = _statuses[profile.id];
      if (status == null ||
          status.isConnected ||
          _connecting.contains(profile.id)) {
        continue;
      }
      unawaited(connect(profile.id));
    }
  }

  Future<void> _connectWithRetry(DcsDeviceProfile profile) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= _retryPolicy.maxAttempts; attempt += 1) {
      if (attempt > 1) {
        final delay = _retryPolicy.delayForAttempt(attempt);
        _setStatus(
          profile.id,
          DcsDeviceConnectionState.retrying,
          message: 'Retrying ${profile.label} in ${delay.inMilliseconds}ms.',
          attempt: attempt,
        );
        await Future<void>.delayed(delay);
      }

      final device =
          _lastDiscovery[profile.id] ?? await _discoverProfile(profile);
      if (device == null) {
        lastError = DcsDeviceConnectionException(
          'No matching device for ${profile.label}.',
        );
        _setStatus(
          profile.id,
          DcsDeviceConnectionState.disconnected,
          message: 'No matching ${profile.label} found.',
          attempt: attempt,
          error: lastError,
        );
        continue;
      }

      try {
        _setStatus(
          profile.id,
          DcsDeviceConnectionState.connecting,
          message: 'Connecting ${profile.label} on ${device.portName}.',
          attempt: attempt,
          device: device,
          clearError: true,
        );

        final adapter = _adapterFor(profile.transport);
        final session = await adapter.connect(profile, device);
        _sessions[profile.id] = session;
        _attachData(profile.id, session);
        _startHealthCheck(profile.id, session);

        _setStatus(
          profile.id,
          DcsDeviceConnectionState.connected,
          message: '${profile.label} connected on ${device.portName}.',
          attempt: attempt,
          device: device,
          clearError: true,
        );
        _log(DcsLogLevel.info, 'Connected device.', profileId: profile.id);
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        _log(
          DcsLogLevel.warning,
          'Connection attempt failed.',
          profileId: profile.id,
          error: error,
          stackTrace: stackTrace,
          data: {'attempt': attempt},
        );
      }
    }

    _setStatus(
      profile.id,
      DcsDeviceConnectionState.failed,
      message: 'Could not connect ${profile.label}.',
      attempt: _retryPolicy.maxAttempts,
      error: lastError,
    );
    _log(
      DcsLogLevel.error,
      'Device connection failed.',
      profileId: profile.id,
      error: lastError,
      stackTrace: lastStackTrace,
    );
  }

  Future<DcsDiscoveredDevice?> _discoverProfile(
    DcsDeviceProfile profile,
  ) async {
    final discoveries = await discover();
    return _bestMatch(profile, discoveries);
  }

  DcsDiscoveredDevice? _bestMatch(
    DcsDeviceProfile profile,
    List<DcsDiscoveredDevice> discoveries,
  ) {
    for (final device in discoveries) {
      if (device.transport == profile.transport &&
          profile.matcher.matches(device)) {
        return device;
      }
    }
    return null;
  }

  void _attachData(String profileId, DcsDeviceSession session) {
    unawaited(_dataSubscriptions.remove(profileId)?.cancel());
    final controller = _dataControllerFor(profileId);
    _dataSubscriptions[profileId] = session.data.listen(
      controller.add,
      onError: controller.addError,
    );
  }

  void _startHealthCheck(String profileId, DcsDeviceSession session) {
    _healthTimers.remove(profileId)?.cancel();
    _missedHeartbeats[profileId] = 0;

    _healthTimers[profileId] = Timer.periodic(_healthPolicy.heartbeatInterval, (
      _,
    ) async {
      try {
        await session.ping();
        _missedHeartbeats[profileId] = 0;
        final status = _statuses[profileId];
        if (status != null &&
            status.state == DcsDeviceConnectionState.degraded) {
          _setStatus(
            profileId,
            DcsDeviceConnectionState.connected,
            message: 'Connection recovered.',
            clearError: true,
          );
        }
      } catch (error, stackTrace) {
        final missed = (_missedHeartbeats[profileId] ?? 0) + 1;
        _missedHeartbeats[profileId] = missed;

        if (missed <= _healthPolicy.maxMissedHeartbeats) {
          _setStatus(
            profileId,
            DcsDeviceConnectionState.degraded,
            message: 'Missed device heartbeat.',
            error: error,
          );
          return;
        }

        _log(
          DcsLogLevel.warning,
          'Device heartbeat failed.',
          profileId: profileId,
          error: error,
          stackTrace: stackTrace,
        );
        await disconnect(profileId);
        if (_config.autoReconnect && !_closed) {
          unawaited(connect(profileId));
        }
      }
    });
  }

  StreamController<List<int>> _dataControllerFor(String profileId) {
    return _dataControllers.putIfAbsent(
      profileId,
      () => StreamController<List<int>>.broadcast(),
    );
  }

  DcsDeviceRequestQueue _requestQueueFor(
    String profileId,
    DcsDeviceRequestOptions options,
  ) {
    final session = _sessions[profileId];
    if (session == null) {
      throw DcsDeviceConnectionException(
        'No active session for profile $profileId.',
      );
    }

    return _requestQueues.putIfAbsent(
      profileId,
      () => DcsDeviceRequestQueue(session, defaultOptions: options),
    );
  }

  DcsDeviceAdapter _adapterFor(DcsDeviceTransport transport) {
    for (final adapter in _adapters) {
      if (adapter.transport == transport) return adapter;
    }
    throw DcsDeviceConnectionException(
      'No adapter registered for ${transport.name}.',
    );
  }

  DcsDeviceProfile? _profileById(String profileId) {
    for (final profile in _config.profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  void _seedStatuses(List<DcsDeviceProfile> profiles) {
    for (final profile in profiles) {
      _statuses.putIfAbsent(
        profile.id,
        () => DcsDeviceStatus.initial(profile.id),
      );
    }
  }

  void _setStatus(
    String profileId,
    DcsDeviceConnectionState state, {
    String? message,
    int? attempt,
    DcsDiscoveredDevice? device,
    Object? error,
    bool clearError = false,
  }) {
    final current = _statuses[profileId] ?? DcsDeviceStatus.initial(profileId);
    _statuses[profileId] = current.copyWith(
      state: state,
      message: message,
      attempt: attempt,
      device: device,
      error: error,
      clearError: clearError,
    );
    _emitStatuses();
  }

  void _emitStatuses() {
    if (!_statusController.isClosed) {
      _statusController.add(Map.unmodifiable(_statuses));
    }
  }

  void _log(
    DcsLogLevel level,
    String message, {
    String? profileId,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    final logger = _logger;
    if (logger == null) return;
    logger(
      DcsLogEvent(
        level: level,
        message: message,
        timestamp: DateTime.now(),
        profileId: profileId,
        error: error,
        stackTrace: stackTrace,
        data: data,
      ),
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('DcsDeviceController is disposed.');
    }
  }
}
