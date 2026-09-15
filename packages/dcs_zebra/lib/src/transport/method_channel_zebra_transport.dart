// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/services.dart';

import '../zebra_logger.dart';
import '../zebra_models.dart';
import 'zebra_transport.dart';

/// Native Link-OS / WinRT transport for Bluetooth and USB (and optional native TCP).
class MethodChannelZebraTransport implements ZebraTransport {
  MethodChannelZebraTransport({
    required this.descriptor,
    ZebraLogger? logger,
    MethodChannel? channel,
  })  : _logger = logger,
        _channel = channel ?? const MethodChannel('dcs_zebra');

  static const MethodChannel defaultChannel = MethodChannel('dcs_zebra');

  final ZebraPrinterDescriptor descriptor;
  final ZebraLogger? _logger;
  final MethodChannel _channel;
  var _connected = false;

  @override
  ZebraConnectionType get connectionType => descriptor.connectionType;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect({Duration? timeout}) async {
    _logger?.call(
      ZebraLogLevel.info,
      ZebraLogScope.transport,
      'Native connect ${descriptor.connectionType.name} ${descriptor.address}',
      printerId: descriptor.id,
    );
    try {
      await _channel.invokeMethod<void>('connect', {
        'id': descriptor.id,
        'address': descriptor.address,
        'connectionType': descriptor.connectionType.name,
        'timeoutMs': (timeout ?? const Duration(seconds: 10)).inMilliseconds,
      });
      _connected = true;
    } on MissingPluginException catch (error) {
      _connected = false;
      throw ZebraRequestFailure(
        'Native Zebra plugin is not available on this platform '
        'for ${descriptor.connectionType.name}.',
        cause: error,
      );
    } on PlatformException catch (error, stack) {
      _connected = false;
      _logger?.call(
        ZebraLogLevel.error,
        ZebraLogScope.transport,
        'Native connect failed',
        printerId: descriptor.id,
        error: error,
        stackTrace: stack,
      );
      throw ZebraRequestFailure(error.message ?? 'Native connect failed', cause: error);
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    try {
      await _channel.invokeMethod<void>('disconnect', {'id': descriptor.id});
    } catch (_) {
      // Best-effort close.
    } finally {
      _connected = false;
    }
  }

  @override
  Future<void> write(Uint8List data, {Duration? timeout}) async {
    if (!_connected) {
      throw const ZebraRequestFailure('Native transport is not connected.');
    }
    await _channel.invokeMethod<void>('write', {
      'id': descriptor.id,
      'bytes': data,
      'timeoutMs': (timeout ?? const Duration(seconds: 30)).inMilliseconds,
    });
  }

  @override
  Future<Uint8List?> read({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!_connected) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>('read', {
        'id': descriptor.id,
        'timeoutMs': timeout.inMilliseconds,
      });
      return result;
    } on PlatformException {
      return null;
    }
  }

  static Future<List<ZebraPrinterDescriptor>> discover({
    required List<ZebraConnectionType> types,
    Duration timeout = const Duration(seconds: 8),
    MethodChannel channel = defaultChannel,
    ZebraLogger? logger,
  }) async {
    try {
      final raw = await channel.invokeMethod<List<Object?>>('discover', {
        'types': types.map((t) => t.name).toList(growable: false),
        'timeoutMs': timeout.inMilliseconds,
      });
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((item) {
            final map = Map<Object?, Object?>.from(item);
            final typeName = (map['connectionType'] as String?) ?? 'tcp';
            final type = ZebraConnectionType.values.firstWhere(
              (value) => value.name == typeName,
              orElse: () => ZebraConnectionType.tcp,
            );
            final address = (map['address'] as String?) ?? '';
            final id = (map['id'] as String?) ?? '${type.name}:$address';
            return ZebraPrinterDescriptor(
              id: id,
              address: address,
              connectionType: type,
              name: (map['name'] as String?) ?? '',
              macAddress: map['macAddress'] as String?,
              serialNumber: map['serialNumber'] as String?,
              model: map['model'] as String?,
            );
          })
          .toList(growable: false);
    } on MissingPluginException {
      logger?.call(
        ZebraLogLevel.debug,
        ZebraLogScope.client,
        'Native discovery unavailable; use TCP endpoints.',
      );
      return const [];
    } on PlatformException catch (error, stack) {
      logger?.call(
        ZebraLogLevel.warning,
        ZebraLogScope.client,
        'Native discovery failed',
        error: error,
        stackTrace: stack,
      );
      return const [];
    }
  }

  static Future<Map<Object?, Object?>?> queryNativeStatus({
    required String printerId,
    MethodChannel channel = defaultChannel,
  }) async {
    try {
      final result = await channel.invokeMethod<Map<Object?, Object?>>(
        'getStatus',
        {'id': printerId},
      );
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<Map<String, bool>> platformCapabilities({
    MethodChannel channel = defaultChannel,
  }) async {
    try {
      final result = await channel.invokeMethod<Map<Object?, Object?>>(
        'capabilities',
      );
      if (result == null) {
        return const {
          'tcp': true,
          'bluetooth': false,
          'bluetoothLe': false,
          'usb': false,
        };
      }
      return {
        'tcp': result['tcp'] != false,
        'bluetooth': result['bluetooth'] == true,
        'bluetoothLe': result['bluetoothLe'] == true,
        'usb': result['usb'] == true,
      };
    } on MissingPluginException {
      return const {
        'tcp': true,
        'bluetooth': false,
        'bluetoothLe': false,
        'usb': false,
      };
    }
  }
}
