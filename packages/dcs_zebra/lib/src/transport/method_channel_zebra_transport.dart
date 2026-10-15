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
  static const EventChannel discoverEventChannel =
      EventChannel('dcs_zebra/discover');

  final ZebraPrinterDescriptor descriptor;
  final ZebraLogger? _logger;
  final MethodChannel _channel;
  var _connected = false;

  static StreamSubscription<dynamic>? _discoverSubscription;

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
          .map((item) => ZebraPrinterDescriptor.fromMap(
                Map<Object?, Object?>.from(item),
              ))
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

  /// Streams printers as the platform finds them (EventChannel), falling back to
  /// a one-shot [discover] if the event channel is unavailable.
  static Stream<ZebraPrinterDescriptor> discoverStream({
    required List<ZebraConnectionType> types,
    Duration timeout = const Duration(seconds: 8),
    MethodChannel channel = defaultChannel,
    EventChannel eventChannel = discoverEventChannel,
    ZebraLogger? logger,
  }) {
    final controller = StreamController<ZebraPrinterDescriptor>();
    var started = false;

    Future<void> start() async {
      if (started) return;
      started = true;
      final seen = <String>{};

      void emit(ZebraPrinterDescriptor descriptor) {
        if (!seen.add(descriptor.id)) return;
        if (!controller.isClosed) controller.add(descriptor);
      }

      try {
        await cancelDiscoverStream(channel: channel);

        // Listen before startDiscover so early native events are not dropped.
        var streamFailed = false;
        _discoverSubscription = eventChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is Map) {
              final map = Map<Object?, Object?>.from(event);
              if (map['done'] == true) {
                if (!controller.isClosed) controller.close();
                return;
              }
              emit(ZebraPrinterDescriptor.fromMap(map));
            }
          },
          onError: (Object error, StackTrace stack) {
            streamFailed = true;
            logger?.call(
              ZebraLogLevel.warning,
              ZebraLogScope.client,
              'Discovery stream error; falling back to one-shot discover',
              error: error,
              stackTrace: stack,
            );
            unawaited(_fallbackDiscover(
              types: types,
              timeout: timeout,
              channel: channel,
              logger: logger,
              emit: emit,
              controller: controller,
            ));
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
          cancelOnError: false,
        );
        // Give the platform stream a tick to attach.
        await Future<void>.delayed(Duration.zero);
        if (streamFailed) return;

        await channel.invokeMethod<void>('startDiscover', {
          'types': types.map((t) => t.name).toList(growable: false),
          'timeoutMs': timeout.inMilliseconds,
        });

        // Safety timeout in case the platform never sends `done`.
        Future<void>.delayed(timeout + const Duration(seconds: 1), () {
          if (!controller.isClosed) controller.close();
        });
      } on MissingPluginException {
        await _fallbackDiscover(
          types: types,
          timeout: timeout,
          channel: channel,
          logger: logger,
          emit: emit,
          controller: controller,
        );
      } on PlatformException catch (error, stack) {
        // Older plugins without startDiscover — fall back.
        if (error.code == 'notImplemented' ||
            error.code == 'MethodNotImplemented' ||
            error.message?.contains('not implemented') == true) {
          await _fallbackDiscover(
            types: types,
            timeout: timeout,
            channel: channel,
            logger: logger,
            emit: emit,
            controller: controller,
          );
          return;
        }
        logger?.call(
          ZebraLogLevel.warning,
          ZebraLogScope.client,
          'startDiscover failed; falling back',
          error: error,
          stackTrace: stack,
        );
        await _fallbackDiscover(
          types: types,
          timeout: timeout,
          channel: channel,
          logger: logger,
          emit: emit,
          controller: controller,
        );
      }
    }

    controller.onListen = () {
      unawaited(start());
    };
    controller.onCancel = () async {
      await cancelDiscoverStream(channel: channel);
    };

    return controller.stream;
  }

  static Future<void> _fallbackDiscover({
    required List<ZebraConnectionType> types,
    required Duration timeout,
    required MethodChannel channel,
    required void Function(ZebraPrinterDescriptor) emit,
    required StreamController<ZebraPrinterDescriptor> controller,
    ZebraLogger? logger,
  }) async {
    final list = await discover(
      types: types,
      timeout: timeout,
      channel: channel,
      logger: logger,
    );
    for (final item in list) {
      emit(item);
    }
    if (!controller.isClosed) await controller.close();
  }

  static Future<void> cancelDiscoverStream({
    MethodChannel channel = defaultChannel,
  }) async {
    await _discoverSubscription?.cancel();
    _discoverSubscription = null;
    try {
      await channel.invokeMethod<void>('cancelDiscover');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
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
          'serial': false,
        };
      }
      return {
        'tcp': result['tcp'] != false,
        'bluetooth': result['bluetooth'] == true,
        'bluetoothLe': result['bluetoothLe'] == true,
        'usb': result['usb'] == true,
        'serial': result['serial'] == true,
      };
    } on MissingPluginException {
      return const {
        'tcp': true,
        'bluetooth': false,
        'bluetoothLe': false,
        'usb': false,
        'serial': false,
      };
    }
  }

  static Future<ZebraPairingResult> pair(
    ZebraPrinterDescriptor descriptor, {
    MethodChannel channel = defaultChannel,
  }) async {
    return _pairingCall('pair', descriptor, channel: channel);
  }

  static Future<ZebraPairingResult> unpair(
    ZebraPrinterDescriptor descriptor, {
    MethodChannel channel = defaultChannel,
  }) async {
    return _pairingCall('unpair', descriptor, channel: channel);
  }

  static Future<ZebraPairingResult> _pairingCall(
    String method,
    ZebraPrinterDescriptor descriptor, {
    required MethodChannel channel,
  }) async {
    try {
      final raw = await channel.invokeMethod<Object?>(method, {
        'id': descriptor.id,
        'address': descriptor.address,
        'connectionType': descriptor.connectionType.name,
        'name': descriptor.name,
        'macAddress': descriptor.macAddress,
      });
      return _parsePairingResult(raw);
    } on MissingPluginException {
      return ZebraPairingResult.unsupported;
    } on PlatformException catch (error) {
      if (error.code == 'unsupported') {
        return ZebraPairingResult.unsupported;
      }
      if (error.code == 'open_settings' ||
          error.message == 'openSystemSettings') {
        return ZebraPairingResult.openSystemSettings;
      }
      return ZebraPairingResult.failed;
    }
  }

  static ZebraPairingResult _parsePairingResult(Object? raw) {
    final name = raw is String
        ? raw
        : (raw is Map ? (raw['result'] as String?) : null);
    switch (name) {
      case 'paired':
        return ZebraPairingResult.paired;
      case 'unpaired':
        return ZebraPairingResult.unpaired;
      case 'alreadyPaired':
        return ZebraPairingResult.alreadyPaired;
      case 'openSystemSettings':
        return ZebraPairingResult.openSystemSettings;
      case 'unsupported':
        return ZebraPairingResult.unsupported;
      default:
        return ZebraPairingResult.failed;
    }
  }

  static Future<List<ZebraPrinterDescriptor>> bondedPrinters({
    MethodChannel channel = defaultChannel,
  }) async {
    return _listPrintersMethod('bondedPrinters', channel: channel);
  }

  static Future<List<ZebraPrinterDescriptor>> pairedAccessories({
    MethodChannel channel = defaultChannel,
  }) async {
    return _listPrintersMethod('pairedAccessories', channel: channel);
  }

  static Future<List<ZebraPrinterDescriptor>> _listPrintersMethod(
    String method, {
    required MethodChannel channel,
  }) async {
    try {
      final raw = await channel.invokeMethod<List<Object?>>(method);
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((item) => ZebraPrinterDescriptor.fromMap(
                Map<Object?, Object?>.from(item),
              ))
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<ZebraPermissionState> ensureBluetoothPermissions({
    MethodChannel channel = defaultChannel,
  }) async {
    try {
      final raw =
          await channel.invokeMethod<Object?>('ensureBluetoothPermissions');
      final name = raw is String
          ? raw
          : (raw is Map ? (raw['state'] as String?) : null);
      switch (name) {
        case 'granted':
          return ZebraPermissionState.granted;
        case 'denied':
          return ZebraPermissionState.denied;
        case 'permanentlyDenied':
          return ZebraPermissionState.permanentlyDenied;
        case 'restricted':
          return ZebraPermissionState.restricted;
        case 'unsupported':
          return ZebraPermissionState.unsupported;
        default:
          return ZebraPermissionState.denied;
      }
    } on MissingPluginException {
      return ZebraPermissionState.unsupported;
    } on PlatformException {
      return ZebraPermissionState.denied;
    }
  }
}
