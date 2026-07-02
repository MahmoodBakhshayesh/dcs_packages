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
    Object? error,
    bool clearError,
  });
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

  Future<CuppsCommandResult> refreshStatus({Duration? timeout}) {
    return _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.deviceStatusRequest(messageId: messageId),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Refreshing status.',
    );
  }

  Future<CuppsCommandResult> acquire({
    required String deviceToken,
    required String airlineId,
    Duration? timeout,
  }) async {
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
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.acquired,
        'Device acquired.',
        acquired: true,
        clearError: true,
      );
    }
    return result;
  }

  Future<CuppsCommandResult> lock({Duration? timeout}) async {
    final result = await _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.deviceLockRequest(messageId: messageId),
      timeout: timeout,
      busyState: CuppsDeviceState.locking,
      busyMessage: 'Locking device.',
    );
    if (result.ok) {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.locked,
        'Device locked.',
        locked: true,
        clearError: true,
      );
    }
    return result;
  }

  Future<CuppsCommandResult> unlock({Duration? timeout}) async {
    final result = await _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.deviceUnlockRequest(messageId: messageId),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Unlocking device.',
    );
    if (result.ok) {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.initialized,
        'Device unlocked.',
        locked: false,
        clearError: true,
      );
    }
    return result;
  }

  Future<CuppsCommandResult> release({Duration? timeout}) async {
    final result = await _sender.sendDeviceRequest(
      descriptor,
      (messageId) => CuppsXml.deviceReleaseRequest(messageId: messageId),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Releasing device.',
    );
    if (result.ok) {
      _sender.updateDeviceStatus(
        descriptor,
        CuppsDeviceState.connected,
        'Device released.',
        acquired: false,
        locked: false,
        clearError: true,
      );
    }
    return result;
  }

  Future<CuppsCommandResult> aeaRequest(String command, {Duration? timeout}) {
    return _sender.sendDeviceRequest(
      descriptor,
      (messageId) =>
          CuppsXml.aeaRequest(messageId: messageId, command: command),
      timeout: timeout,
      busyState: CuppsDeviceState.busy,
      busyMessage: 'Sending AEA command.',
    );
  }

  Future<CuppsCommandResult> print(
    String document, {
    String documentId = '',
    String stockName = '',
    Duration? timeout,
  }) {
    return _sender.sendDeviceRequest(
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
  }
}
