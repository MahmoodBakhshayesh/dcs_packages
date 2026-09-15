// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'transport/method_channel_zebra_transport.dart';
import 'transport/tcp_zebra_transport.dart';
import 'transport/zebra_transport.dart';
import 'zebra_logger.dart';
import 'zebra_models.dart';
import 'zebra_status_parser.dart';

typedef ZebraStatusUpdater = void Function(ZebraPrinterStatus status);

/// Single Zebra printer session (TCP / Bluetooth / USB).
class ZebraPrinter {
  ZebraPrinter({
    required this.descriptor,
    required ZebraLogger logger,
    required ZebraStatusUpdater onStatus,
    ZebraConnectionOptions options = const ZebraConnectionOptions(),
    ZebraTransport? transport,
  })  : _logger = logger,
        _onStatus = onStatus,
        _options = options,
        _transport = transport,
        _status = ZebraPrinterStatus.discovered(descriptor);

  final ZebraPrinterDescriptor descriptor;
  final ZebraLogger _logger;
  final ZebraStatusUpdater _onStatus;
  final ZebraConnectionOptions _options;
  ZebraTransport? _transport;
  ZebraPrinterStatus _status;

  String get id => descriptor.id;

  ZebraPrinterRole get role => descriptor.role;

  ZebraPrinterStatus get status => _status;

  bool get isConnected => _transport?.isConnected == true;

  Future<void> connect({Duration? timeout}) async {
    _setStatus(
      _status.copyWith(
        state: ZebraPrinterState.connecting,
        message: 'Connecting',
        clearError: true,
      ),
    );

    final transport = _transport ?? _createTransport();
    _transport = transport;

    try {
      await transport.connect(timeout: timeout ?? _options.connectTimeout);
      _setStatus(
        _status.copyWith(
          state: ZebraPrinterState.connected,
          message: 'Connected',
          connected: true,
          clearError: true,
        ),
      );
      _logger.call(
        ZebraLogLevel.info,
        ZebraLogScope.device,
        'Printer connected',
        printerId: id,
        data: {
          'type': descriptor.connectionType.name,
          'address': descriptor.address,
        },
      );

      if (_options.autoQueryStatusAfterConnect) {
        try {
          await queryStatus(timeout: _options.statusTimeout);
        } catch (error, stack) {
          _logger.call(
            ZebraLogLevel.warning,
            ZebraLogScope.device,
            'Post-connect status query failed',
            printerId: id,
            error: error,
            stackTrace: stack,
          );
        }
      }
    } catch (error, stack) {
      _setStatus(
        _status.copyWith(
          state: ZebraPrinterState.failed,
          message: 'Connect failed',
          connected: false,
          lastError: error,
        ),
      );
      _logger.call(
        ZebraLogLevel.error,
        ZebraLogScope.device,
        'Connect failed',
        printerId: id,
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final transport = _transport;
    _transport = null;
    await transport?.disconnect();
    _setStatus(
      _status.copyWith(
        state: ZebraPrinterState.disconnected,
        message: 'Disconnected',
        connected: false,
        readyToPrint: false,
        printing: false,
        clearHardwareStatus: true,
      ),
    );
    _logger.call(
      ZebraLogLevel.info,
      ZebraLogScope.device,
      'Printer disconnected',
      printerId: id,
    );
  }

  Future<ZebraCommandResult> printZpl(
    String zpl, {
    Duration? timeout,
  }) {
    return printRaw(zpl, timeout: timeout, language: ZebraPrinterLanguage.zpl);
  }

  Future<ZebraCommandResult> printCpcl(
    String cpcl, {
    Duration? timeout,
  }) {
    return printRaw(
      cpcl,
      timeout: timeout,
      language: ZebraPrinterLanguage.cpcl,
    );
  }

  Future<ZebraCommandResult> printRaw(
    String data, {
    Duration? timeout,
    ZebraPrinterLanguage language = ZebraPrinterLanguage.unknown,
  }) async {
    final transport = _requireTransport();
    final payload = data.trimRight();
    if (payload.isEmpty) {
      return const ZebraCommandResult(
        ok: false,
        result: 'empty',
        message: 'Print payload is empty.',
      );
    }

    _setStatus(
      _status.copyWith(
        state: ZebraPrinterState.printing,
        message: 'Printing',
        printing: true,
        clearError: true,
      ),
    );
    _logger.call(
      ZebraLogLevel.info,
      ZebraLogScope.device,
      'Printing ${language.name} (${payload.length} chars)',
      printerId: id,
      direction: ZebraMessageDirection.outbound,
      payload: payload.length > 2000 ? '${payload.substring(0, 2000)}…' : payload,
    );

    try {
      await transport.write(
        Uint8List.fromList(utf8.encode(payload.endsWith('\n') ? payload : '$payload\n')),
        timeout: timeout ?? _options.writeTimeout,
      );
      _setStatus(
        _status.copyWith(
          state: ZebraPrinterState.ready,
          message: 'Print sent',
          printing: false,
          readyToPrint: true,
          language: language,
          clearError: true,
        ),
      );
      return const ZebraCommandResult(
        ok: true,
        result: 'ok',
        message: 'Print sent.',
      );
    } catch (error, stack) {
      _setStatus(
        _status.copyWith(
          state: ZebraPrinterState.failed,
          message: 'Print failed',
          printing: false,
          lastError: error,
        ),
      );
      _logger.call(
        ZebraLogLevel.error,
        ZebraLogScope.device,
        'Print failed',
        printerId: id,
        error: error,
        stackTrace: stack,
      );
      return ZebraCommandResult(
        ok: false,
        result: 'printFailed',
        message: error.toString(),
      );
    }
  }

  Future<ZebraPrinterStatus> queryStatus({Duration? timeout}) async {
    final transport = _requireTransport();

    if (descriptor.connectionType != ZebraConnectionType.tcp) {
      final native = await MethodChannelZebraTransport.queryNativeStatus(
        printerId: id,
      );
      if (native != null) {
        final updated = ZebraStatusParser.fromNativeMap(
          native,
          printer: descriptor,
          previous: _status,
        );
        _setStatus(updated);
        return updated;
      }
    }

    await transport.write(
      ZebraSgd.hostStatusCommand(),
      timeout: timeout ?? _options.statusTimeout,
    );
    final bytes = await transport.read(
      timeout: timeout ?? _options.statusTimeout,
    );
    if (bytes == null || bytes.isEmpty) {
      final updated = _status.copyWith(
        state: ZebraPrinterState.connected,
        message: 'Status pending',
        connected: true,
        hardwareStatusLabel: 'unknown',
      );
      _setStatus(updated);
      return updated;
    }

    final raw = utf8.decode(bytes, allowMalformed: true);
    final updated = ZebraStatusParser.fromHostStatus(
      raw,
      printer: descriptor,
      previous: _status,
    );
    _setStatus(updated);
    _logger.call(
      ZebraLogLevel.debug,
      ZebraLogScope.protocol,
      'Host status: ${updated.hardwareStatusLabel}',
      printerId: id,
      direction: ZebraMessageDirection.inbound,
      payload: raw,
    );
    return updated;
  }

  Future<String?> sgdGet(String name, {Duration? timeout}) async {
    final transport = _requireTransport();
    await transport.write(
      ZebraSgd.getCommand(name),
      timeout: timeout ?? _options.statusTimeout,
    );
    final bytes = await transport.read(
      timeout: timeout ?? _options.statusTimeout,
    );
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true).trim();
  }

  Future<ZebraCommandResult> sgdSet(
    String name,
    String value, {
    Duration? timeout,
  }) async {
    final transport = _requireTransport();
    try {
      await transport.write(
        ZebraSgd.setCommand(name, value),
        timeout: timeout ?? _options.writeTimeout,
      );
      return const ZebraCommandResult(
        ok: true,
        result: 'ok',
        message: 'SGD set sent.',
      );
    } catch (error) {
      return ZebraCommandResult(
        ok: false,
        result: 'sgdSetFailed',
        message: error.toString(),
      );
    }
  }

  Future<bool> waitForReady({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await queryStatus();
        if (status.isUsable) return true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  ZebraTransport _createTransport() {
    switch (descriptor.connectionType) {
      case ZebraConnectionType.tcp:
        final parts = descriptor.address.split(':');
        final host = parts.first;
        final port = parts.length > 1
            ? int.tryParse(parts[1]) ?? _options.defaultTcpPort
            : _options.defaultTcpPort;
        return TcpZebraTransport(
          endpoint: ZebraEndpoint(
            host: host,
            port: port,
            statusPort: _options.defaultStatusPort,
          ),
          logger: _logger,
          printerId: id,
        );
      case ZebraConnectionType.bluetooth:
      case ZebraConnectionType.bluetoothLe:
      case ZebraConnectionType.usb:
        return MethodChannelZebraTransport(
          descriptor: descriptor,
          logger: _logger,
        );
    }
  }

  ZebraTransport _requireTransport() {
    final transport = _transport;
    if (transport == null || !transport.isConnected) {
      throw const ZebraRequestFailure('Printer is not connected.');
    }
    return transport;
  }

  void _setStatus(ZebraPrinterStatus status) {
    _status = status;
    _onStatus(status);
  }
}
