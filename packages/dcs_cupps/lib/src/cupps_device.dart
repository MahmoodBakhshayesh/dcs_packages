// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'cupps_models.dart';
import 'cupps_xml.dart';

abstract interface class CuppsDeviceCommandSender {
  Stream<CuppsDeviceStatus> deviceStatus(String deviceId);

  CuppsDeviceStatus? currentDeviceStatus(String deviceId);

  Future<CuppsCommandResult> sendDeviceRequest(
    CuppsDeviceDescriptor device,
    String Function(int messageId) buildXml, {
    Duration? timeout,
    CuppsDeviceState? busyState,
    String? busyMessage,
  });

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
    bool clearError,
    bool clearHardwareStatus = false,
  });

  Future<CuppsCommandResult> waitForInboundAea(
    String deviceId,
    CuppsAeaWaitKind kind, {
    Duration timeout = const Duration(seconds: 15),
  });

  void registerInboundAeaWait(String deviceId, CuppsAeaWaitKind kind);

  void cancelInboundAeaWait(String deviceId, CuppsAeaWaitKind kind);

  Future<void> closeDeviceSession(
    String deviceId, {
    bool notifyClosed = true,
  });

  Future<CuppsCommandResult> restartDevice(
    String deviceId, {
    required String deviceToken,
    required String airlineId,
    bool relock = true,
    List<String> configureCommands = const [],
  });

  /// When true, client keeps re-locking until unlock/release/disconnect.
  void setPersistentLockDesired(String deviceId, bool desired);
}

class CuppsDevice {
  CuppsDevice({
    required this.descriptor,
    required CuppsDeviceCommandSender sender,
  }) : _sender = sender;

  final CuppsDeviceDescriptor descriptor;
  final CuppsDeviceCommandSender _sender;

  String get id => descriptor.id;

  CuppsDeviceType get type => descriptor.type;

  CuppsDeviceStatus? get status => _sender.currentDeviceStatus(id);

  Stream<CuppsDeviceStatus> get statusStream => _sender.deviceStatus(id);

  /// Full device bring-up after the device socket is connected:
  /// acquire → interface mode → best-effort status refresh.
  Future<CuppsCommandResult> initialize({
    required String deviceToken,
    required String airlineId,
    Duration? timeout,
    bool forceAcquire = false,
  }) async {
    final acquireResult = await acquire(
      deviceToken: deviceToken,
      airlineId: airlineId,
      timeout: timeout,
      force: forceAcquire,
    );
    if (!acquireResult.ok) return acquireResult;

    final modeResult = await interfaceMode(timeout: timeout);
    if (!modeResult.ok) return modeResult;

    final statusResult = await refreshStatus(timeout: timeout);
    if (statusResult.ok) return statusResult;

    return CuppsCommandResult(
      ok: true,
      result: modeResult.result,
      rawXml: modeResult.rawXml,
      message: modeResult.message ?? 'Device initialized (status pending).',
    );
  }

  Future<CuppsCommandResult> refreshStatus({Duration? timeout}) async {
    final statusTimeout = timeout ?? const Duration(seconds: 5);
    CuppsCommandResult? directResult;

    if (!_preferNotifyStatusOnly) {
      try {
        directResult = await _sender.sendDeviceRequest(
          descriptor,
          (messageId) => CuppsXml.deviceStatusRequest(messageId: messageId),
          timeout: statusTimeout,
          busyState: CuppsDeviceState.busy,
          busyMessage: 'Refreshing status.',
        );
        if (directResult.ok) {
          return _finalizeStatusResult(directResult);
        }
      } catch (_) {
        directResult = null;
      }
    }

    final current = status;
    final notifyLabel = current?.hardwareStatusLabel?.trim();
    if (notifyLabel != null && notifyLabel.isNotEmpty) {
      return CuppsCommandResult(
        ok: true,
        result: 'ok',
        rawXml: '',
        message: notifyLabel,
      );
    }

    if (_supportsAeaStatusQuery && notifyLabel == 'ready') {
      final aeaResult = await aeaRequest(
        'ST#A#B',
        timeout: timeout ?? const Duration(seconds: 15),
        waitForDeviceAck: true,
        waitKind: CuppsAeaWaitKind.configure,
      );
      if (aeaResult.ok) {
        _sender.updateDeviceStatus(
          descriptor,
          CuppsDeviceState.initialized,
          aeaResult.message ?? 'Device status refreshed via AEA.',
          initialized: true,
          hardwareStatusLabel: aeaResult.aeaText ?? 'ready',
          clearError: true,
        );
      }
      return aeaResult;
    }

    if (directResult != null) return directResult;

    return CuppsCommandResult(
      ok: false,
      result: 'statusUnavailable',
      rawXml: '',
      message: 'Device status is not available yet.',
    );
  }

  CuppsCommandResult _finalizeStatusResult(CuppsCommandResult result) {
    final hardwareStatus =
        CuppsXml.deviceHardwareStatusLabel(result.rawXml, type);
    if (hardwareStatus != null) {
      if (CuppsHardwareStatus.isOffline(hardwareStatus)) {
        _sender.updateDeviceStatus(
          descriptor,
          CuppsDeviceState.disconnected,
          'Status: $hardwareStatus',
          acquired: false,
          initialized: false,
          locked: false,
          hardwareStatusLabel: hardwareStatus,
          error: hardwareStatus,
          clearError: false,
        );
        return CuppsCommandResult(
          ok: false,
          result: 'powerOff',
          rawXml: result.rawXml,
          message: 'Device is offline (power off).',
        );
      }
      final ready = CuppsHardwareStatus.isReady(hardwareStatus);
      _sender.updateDeviceStatus(
        descriptor,
        ready ? CuppsDeviceState.initialized : CuppsDeviceState.degraded,
        'Status: $hardwareStatus',
        initialized: ready,
        hardwareStatusLabel: hardwareStatus,
        clearError: ready,
        error: ready ? null : hardwareStatus,
      );
      return CuppsCommandResult(
        ok: ready,
        result: result.result,
        rawXml: result.rawXml,
        message: hardwareStatus,
      );
    }

    _sender.updateDeviceStatus(
      descriptor,
      CuppsDeviceState.initialized,
      'Device status refreshed.',
      initialized: true,
      clearError: true,
    );
    return result;
  }

  bool get _supportsAeaStatusQuery {
    return type == CuppsDeviceType.boardingPassPrinter ||
        type == CuppsDeviceType.bagTagPrinter ||
        type == CuppsDeviceType.documentPrinter;
  }

  bool get _preferNotifyStatusOnly {
    return type == CuppsDeviceType.boardingPassPrinter ||
        type == CuppsDeviceType.bagTagPrinter;
  }

  /// BP/BT printers do not use deviceLock in CUPPS; readers / BG / PR do.
  bool get supportsDeviceLock {
    return type == CuppsDeviceType.barcodeReader ||
        type == CuppsDeviceType.boardingGateReader ||
        type == CuppsDeviceType.opticalCardReader ||
        type == CuppsDeviceType.passportReader ||
        type == CuppsDeviceType.documentPrinter;
  }

  /// BG embeds DD; standalone DD also supports CUPPS display requests.
  bool get supportsDisplay {
    return type == CuppsDeviceType.boardingGateReader ||
        type == CuppsDeviceType.displayDevice;
  }

  bool get supportsBarcodeRead {
    return type == CuppsDeviceType.barcodeReader ||
        type == CuppsDeviceType.boardingGateReader;
  }

  Future<bool> waitForHardwareStatus(
    String expected, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final target = expected.trim().toLowerCase();
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final label = status?.hardwareStatusLabel?.trim().toLowerCase();
      if (label == target) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<CuppsCommandResult> acquire({
    required String deviceToken,
    required String airlineId,
    Duration? timeout,
    bool force = false,
  }) async {
    if (!force && status?.acquired == true) {
      return const CuppsCommandResult(
        ok: true,
        result: 'ok',
        rawXml: '',
        message: 'Device already acquired.',
      );
    }

    final result = await _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.deviceAcquireRequest(
        messageId: messageId,
        deviceName: descriptor.name,
        deviceToken: deviceToken,
        airlineId: airlineId,
      ),
      timeout: timeout,
      busyState: CuppsDeviceState.acquiring,
      busyMessage: 'Acquiring device.',
    );
    if (result.ok) {
      final hardware = CuppsXml.deviceHardwareStatusLabel(result.rawXml, type) ??
          CuppsXml.hardwareStatusLabelFromNotify(result.rawXml);
      if (CuppsHardwareStatus.isOffline(hardware)) {
        _sender.updateDeviceStatus(
          descriptor,
          CuppsDeviceState.disconnected,
          'Device is offline (power off).',
          acquired: false,
          initialized: false,
          locked: false,
          hardwareStatusLabel: hardware,
          error: hardware,
          clearError: false,
        );
        return CuppsCommandResult(
          ok: false,
          result: 'powerOff',
          rawXml: result.rawXml,
          message: 'Device is offline (power off).',
        );
      }
      if (CuppsHardwareStatus.isInUseByOthers(hardware, result: result.result)) {
        _sender.updateDeviceStatus(
          descriptor,
          CuppsDeviceState.degraded,
          'Device locked by others.',
          acquired: false,
          initialized: false,
          locked: false,
          hardwareStatusLabel: hardware,
          error: 'Locked by others',
          clearError: false,
        );
        return CuppsCommandResult(
          ok: false,
          result: result.result,
          rawXml: result.rawXml,
          message: 'Device locked by others.',
        );
      }
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.acquired,
        'Device acquired.',
        acquired: true,
        hardwareStatusLabel: hardware,
        clearError: true,
      );
    } else if (CuppsHardwareStatus.isInUseByOthers(
      null,
      result: result.result,
      error: result.message,
    )) {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.degraded,
        'Device locked by others.',
        acquired: false,
        error: 'Locked by others',
        clearError: false,
      );
    }
    return result;
  }

  Future<CuppsCommandResult> interfaceMode({
    String? mode,
    Duration? timeout,
  }) async {
    final resolvedMode = _resolveInterfaceMode(mode);
    final result = await _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.interfaceModeRequest(
        messageId: messageId,
        mode: resolvedMode,
      ),
      timeout: timeout,
      busyState: CuppsDeviceState.initializing,
      busyMessage: 'Setting interface mode $resolvedMode.',
    );
    if (result.ok) {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.initialized,
        'Interface mode $resolvedMode set.',
        initialized: true,
        clearError: true,
      );
    }
    return result;
  }

  Future<CuppsCommandResult> lock({Duration? timeout, bool renew = false}) async {
    if (!supportsDeviceLock) {
      return const CuppsCommandResult(
        ok: false,
        result: 'illogicalAction',
        rawXml: '',
        message: 'This device type does not support deviceLock.',
      );
    }
    final result = await _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.deviceLockRequest(
        messageId: messageId,
        renew: renew,
      ),
      timeout: timeout,
      busyState: CuppsDeviceState.locking,
      busyMessage: renew ? 'Renewing device lock.' : 'Locking device.',
    );
    if (result.ok) {
      _sender.setPersistentLockDesired(id, true);
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.locked,
        renew ? 'Device lock renewed.' : 'Device locked.',
        locked: true,
        clearError: true,
      );
    }
    return result;
  }

  Future<CuppsCommandResult> unlock({Duration? timeout}) async {
    if (!supportsDeviceLock) {
      return const CuppsCommandResult(
        ok: true,
        result: 'ok',
        rawXml: '',
        message: 'Unlock not required for this device type.',
      );
    }
    _sender.setPersistentLockDesired(id, false);
    final result = await _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.deviceUnlockRequest(messageId: messageId),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Unlocking device.',
    );
    if (result.ok || result.result.toLowerCase() == 'devicenotlocked') {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.initialized,
        'Device unlocked.',
        locked: false,
        clearError: true,
      );
      return CuppsCommandResult(
        ok: true,
        result: result.result,
        rawXml: result.rawXml,
        message: result.message,
      );
    }
    return result;
  }

  Future<CuppsCommandResult> release({
    Duration? timeout,
    bool closeSocket = true,
  }) async {
    CuppsCommandResult? result;

    _sender.setPersistentLockDesired(id, false);

    if (status?.acquired == true) {
      if (status?.locked == true) {
        await unlock(timeout: timeout);
      }

      try {
        result = await _sender.sendDeviceRequest(
          descriptor,
          (messageId) => CuppsXml.deviceReleaseRequest(messageId: messageId),
          timeout: timeout,
          busyState: CuppsDeviceState.busy,
          busyMessage: 'Releasing device.',
        );
      } catch (error) {
        result = CuppsCommandResult(
          ok: false,
          result: 'releaseFailed',
          rawXml: '',
          message: error.toString(),
        );
      }
    } else {
      result = const CuppsCommandResult(
        ok: true,
        result: 'ok',
        rawXml: '',
        message: 'Device was not acquired.',
      );
    }

    if (closeSocket) {
      await _sender.closeDeviceSession(id);
    } else if (result.ok) {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.connected,
        'Device released.',
        acquired: false,
        locked: false,
        initialized: false,
        clearError: true,
        clearHardwareStatus: true,
      );
    }

    if (result.ok || closeSocket) {
      return CuppsCommandResult(
        ok: true,
        result: result.result,
        rawXml: result.rawXml,
        message: closeSocket && !result.ok
            ? 'Device session closed (${result.message}).'
            : result.message ?? 'Device released.',
      );
    }

    return result;
  }

  /// Release, close socket, reconnect, and re-initialize the device session.
  Future<CuppsCommandResult> restart({
    required String deviceToken,
    required String airlineId,
    Duration? timeout,
    bool relock = true,
    List<String> configureCommands = const [],
  }) {
    return _sender.restartDevice(
      id,
      deviceToken: deviceToken,
      airlineId: airlineId,
      relock: relock,
      configureCommands: configureCommands,
    );
  }

  Future<CuppsCommandResult> completeConfigure(
    List<String> commands, {
    Duration? commandTimeout,
    bool tolerateMissingDeviceAck = true,
    Duration deviceAckTimeout = const Duration(milliseconds: 300),
  }) async {
    if (status?.acquired != true) {
      return const CuppsCommandResult(
        ok: false,
        result: 'notAcquired',
        rawXml: '',
        message: 'Device must be acquired before configure commands.',
      );
    }

    final timeout = commandTimeout ?? const Duration(seconds: 20);
    CuppsCommandResult? lastResult;

    _sender.updateDeviceStatus(
      descriptor,
      CuppsDeviceState.busy,
      'Configuring device.',
      configuring: true,
      clearError: true,
    );

    try {
      for (final rawCommand in commands) {
        final command = rawCommand.replaceAll('\r', '').trim();
        if (command.isEmpty) continue;

        _sender.registerInboundAeaWait(id, CuppsAeaWaitKind.configure);
        try {
          final outbound = await _sender.sendDeviceRequest(
            descriptor,
            (messageId) =>
                CuppsXml.aeaRequest(messageId: messageId, command: command),
            timeout: timeout,
            busyState: CuppsDeviceState.busy,
            busyMessage: 'Configuring device.',
          );
          if (!outbound.ok) {
            lastResult = outbound;
            break;
          }

          final ackTimeout = tolerateMissingDeviceAck
              ? deviceAckTimeout
              : const Duration(seconds: 15);
          CuppsCommandResult ack;
          try {
            ack = await _sender.waitForInboundAea(
              id,
              CuppsAeaWaitKind.configure,
              timeout: ackTimeout,
            );
          } catch (_) {
            ack = const CuppsCommandResult(
              ok: false,
              result: 'timeout',
              rawXml: '',
              message: 'Timed out waiting for configure acknowledgement.',
            );
          }

          if (ack.ok) {
            lastResult = ack;
            continue;
          }

          if (tolerateMissingDeviceAck && outbound.ok) {
            lastResult = CuppsCommandResult(
              ok: true,
              result: outbound.result,
              rawXml: outbound.rawXml,
              message: 'Configure accepted (outbound OK).',
            );
            continue;
          }

          lastResult = ack;
          break;
        } finally {
          _sender.cancelInboundAeaWait(id, CuppsAeaWaitKind.configure);
        }
      }
    } catch (error) {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.failed,
        'Configure sequence failed.',
        configuring: false,
        error: error,
        clearError: false,
      );
      rethrow;
    }

    final result = lastResult ??
        const CuppsCommandResult(
          ok: false,
          result: 'empty',
          rawXml: '',
          message: 'No configure commands were provided.',
        );

    if (result.ok) {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.initialized,
        'Device configured.',
        initialized: true,
        configuring: false,
        clearError: true,
      );
    } else {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.degraded,
        result.message ?? 'Configure sequence failed.',
        configuring: false,
        error: result.result,
        clearError: false,
      );
    }

    return result;
  }

  Future<CuppsCommandResult> aeaRequest(
    String command, {
    Duration? timeout,
    bool waitForDeviceAck = false,
    CuppsAeaWaitKind waitKind = CuppsAeaWaitKind.configure,
  }) async {
    if (waitForDeviceAck) {
      _sender.registerInboundAeaWait(id, waitKind);
    }

    try {
      final result = await _sender.sendDeviceRequest(
        descriptor,
        (messageId) => CuppsXml.aeaRequest(messageId: messageId, command: command),
        timeout: timeout,
        busyState: CuppsDeviceState.busy,
        busyMessage: 'Sending AEA command.',
      );
      if (!result.ok || !waitForDeviceAck) return result;

      final ack = await _sender.waitForInboundAea(
        id,
        waitKind,
        timeout: timeout ?? const Duration(seconds: 15),
      );
      return ack;
    } catch (error) {
      if (waitForDeviceAck) {
        _sender.cancelInboundAeaWait(id, waitKind);
      }
      rethrow;
    }
  }

  Future<CuppsCommandResult> print(
    String document, {
    String documentId = '',
    String stockName = '',
    Duration? timeout,
    bool useAea = true,
    bool tolerateMissingDeviceAck = true,
    Duration deviceAckTimeout = const Duration(seconds: 8),
  }) async {
    if (useAea) {
      if (status?.acquired != true) {
        return const CuppsCommandResult(
          ok: false,
          result: 'notAcquired',
          rawXml: '',
          message: 'Device must be acquired before printing.',
        );
      }

      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.busy,
        'Printing document.',
        printing: true,
        clearError: true,
      );

      _sender.registerInboundAeaWait(id, CuppsAeaWaitKind.print);
      try {
        final outbound = await _sender.sendDeviceRequest(
          descriptor,
          (messageId) => CuppsXml.aeaRequest(messageId: messageId, command: document),
          timeout: timeout,
          busyState: CuppsDeviceState.busy,
          busyMessage: 'Printing document.',
        );
        if (!outbound.ok) return outbound;

        final ackTimeout = tolerateMissingDeviceAck
            ? deviceAckTimeout
            : (timeout ?? const Duration(seconds: 20));
        CuppsCommandResult ack;
        try {
          ack = await _sender.waitForInboundAea(
            id,
            CuppsAeaWaitKind.print,
            timeout: ackTimeout,
          );
        } catch (_) {
          ack = const CuppsCommandResult(
            ok: false,
            result: 'timeout',
            rawXml: '',
            message: 'Timed out waiting for print acknowledgement.',
          );
        }

        if (ack.ok) return ack;

        // Only treat *missing* device ack as soft success. Real AEA errors
        // (e.g. HDCERR2EP) must surface as print failures on PrintBus.
        final isTimeout = ack.result.toLowerCase() == 'timeout';
        if (tolerateMissingDeviceAck && isTimeout) {
          return CuppsCommandResult(
            ok: true,
            result: outbound.result,
            rawXml: outbound.rawXml,
            message: 'Print accepted (outbound OK).',
            aeaText: ack.aeaText,
          );
        }
        return ack;
      } finally {
        _sender.cancelInboundAeaWait(id, CuppsAeaWaitKind.print);
        _sender.updateDeviceStatus(
          descriptor,
          CuppsDeviceState.initialized,
          'Print finished.',
          printing: false,
        );
      }
    }

    final result = await _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.printRequest(
        messageId: messageId,
        document: document,
        documentId: documentId,
        stockName: stockName,
      ),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Printing document.',
    );
    return result;
  }

  /// CUPPS `ddDisplayRequest` — BG (embedded DD) or standalone display.
  Future<CuppsCommandResult> displayLines(
    List<String> lines, {
    Duration? timeout,
    bool clearFirst = true,
  }) async {
    if (!supportsDisplay) {
      return const CuppsCommandResult(
        ok: false,
        result: 'illogicalAction',
        rawXml: '',
        message: 'This device type does not support display.',
      );
    }
    if (status?.acquired != true) {
      return const CuppsCommandResult(
        ok: false,
        result: 'notAcquired',
        rawXml: '',
        message: 'Device must be acquired before display.',
      );
    }
    if (clearFirst) {
      await clearDisplay(timeout: timeout);
    }
    final sanitized = [
      for (final line in lines) line.replaceAll('\r', ' ').trim(),
    ].where((l) => l.isNotEmpty).take(8).toList(growable: false);
    return _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.ddDisplayRequest(
        messageId: messageId,
        lines: sanitized,
      ),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Updating display.',
    );
  }

  Future<CuppsCommandResult> clearDisplay({Duration? timeout}) async {
    if (!supportsDisplay) {
      return const CuppsCommandResult(
        ok: true,
        result: 'ok',
        rawXml: '',
        message: 'Clear display not required for this device type.',
      );
    }
    if (status?.acquired != true) {
      return const CuppsCommandResult(
        ok: false,
        result: 'notAcquired',
        rawXml: '',
        message: 'Device must be acquired before clear display.',
      );
    }
    return _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.ddClearScreenRequest(messageId: messageId),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Clearing display.',
    );
  }

  /// Pull waiting barcode data after a data-available notify (when locked).
  Future<CuppsCommandResult> readWaitingData({Duration? timeout}) async {
    if (!supportsBarcodeRead) {
      return const CuppsCommandResult(
        ok: false,
        result: 'illogicalAction',
        rawXml: '',
        message: 'This device type does not support readerRead.',
      );
    }
    return _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.readerReadRequest(messageId: messageId),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Reading barcode data.',
    );
  }

  String _resolveInterfaceMode(String? mode) {
    if (mode != null && mode.trim().isNotEmpty) return mode.trim();
    if (descriptor.supportedInterfaceModes.isNotEmpty) {
      return descriptor.supportedInterfaceModes.first;
    }
    if (type == CuppsDeviceType.boardingGateReader) return 'aea';
    if (type == CuppsDeviceType.boardingPassPrinter ||
        type == CuppsDeviceType.bagTagPrinter) {
      return 'AEA';
    }
    return 'AEA';
  }
}
