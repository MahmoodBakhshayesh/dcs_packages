// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'transport/method_channel_zebra_transport.dart';
import 'zebra_logger.dart';
import 'zebra_models.dart';
import 'zebra_printer.dart';
import 'zebra_printer_identity.dart';

/// Facade for discovering and managing Zebra printers.
class ZebraClient {
  ZebraClient({
    ZebraConnectionOptions options = const ZebraConnectionOptions(),
    ZebraLogger? logger,
  })  : _options = options,
        logger = logger ?? ZebraLogger();

  final ZebraConnectionOptions _options;
  final ZebraLogger logger;

  final _printers = <String, ZebraPrinter>{};
  final _statuses = <String, ZebraPrinterStatus>{};
  final _statusesController =
      StreamController<Map<String, ZebraPrinterStatus>>.broadcast();
  final _statusControllers = <String, StreamController<ZebraPrinterStatus>>{};

  List<ZebraPrinter> get printers => List.unmodifiable(_printers.values);

  Map<String, ZebraPrinterStatus> get currentStatuses =>
      Map.unmodifiable(_statuses);

  Stream<Map<String, ZebraPrinterStatus>> get statuses =>
      _statusesController.stream;

  Stream<ZebraPrinterStatus> printerStatus(String printerId) {
    return _statusControllers
        .putIfAbsent(printerId, () => StreamController.broadcast())
        .stream;
  }

  ZebraPrinterStatus? currentPrinterStatus(String printerId) =>
      _statuses[printerId];

  ZebraPrinter? printerById(String id) => _printers[id];

  ZebraPrinter? printerByRole(ZebraPrinterRole role) {
    for (final printer in _printers.values) {
      if (printer.role == role && printer.isConnected) return printer;
    }
    for (final printer in _printers.values) {
      if (printer.role == role) return printer;
    }
    return null;
  }

  Future<Map<String, bool>> platformCapabilities() {
    return MethodChannelZebraTransport.platformCapabilities();
  }

  /// Discover printers via native SDK where available.
  ///
  /// Results are filtered to Zebra-like printers only.
  Future<List<ZebraPrinterDescriptor>> discover({
    List<ZebraConnectionType> types = const [
      ZebraConnectionType.tcp,
      ZebraConnectionType.bluetooth,
      ZebraConnectionType.bluetoothLe,
      ZebraConnectionType.usb,
    ],
    Duration timeout = const Duration(seconds: 8),
    bool zebraOnly = true,
  }) async {
    logger.call(
      ZebraLogLevel.info,
      ZebraLogScope.client,
      'Discovering printers: ${types.map((t) => t.name).join(", ")}',
    );
    final raw = await MethodChannelZebraTransport.discover(
      types: types,
      timeout: timeout,
      logger: logger,
    );
    final filtered = zebraOnly ? ZebraPrinterIdentity.onlyZebra(raw) : raw;
    logger.call(
      ZebraLogLevel.info,
      ZebraLogScope.client,
      'Discovery returned ${raw.length} device(s), '
      '${filtered.length} Zebra candidate(s)',
    );
    return filtered;
  }

  /// Register a known TCP / BT / USB printer without connecting yet.
  ZebraPrinter register(ZebraPrinterDescriptor descriptor) {
    final existing = _printers[descriptor.id];
    if (existing != null) return existing;

    final printer = ZebraPrinter(
      descriptor: descriptor,
      logger: logger,
      options: _options,
      onStatus: (status) => _publishStatus(status),
    );
    _printers[descriptor.id] = printer;
    _publishStatus(ZebraPrinterStatus.discovered(descriptor));
    return printer;
  }

  /// Convenience: register + connect a TCP printer.
  Future<ZebraPrinter> connectTcp({
    required String host,
    int? port,
    ZebraPrinterRole role = ZebraPrinterRole.generic,
    String? name,
    String? id,
    Duration? timeout,
  }) async {
    final resolvedPort = port ?? _options.defaultTcpPort;
    final address = '$host:$resolvedPort';
    final descriptor = ZebraPrinterDescriptor(
      id: id ?? 'tcp:$address',
      address: address,
      connectionType: ZebraConnectionType.tcp,
      name: name ?? address,
      role: role,
    );
    final printer = register(descriptor);
    await printer.connect(timeout: timeout);
    return printer;
  }

  /// Register + connect using a fully specified descriptor.
  Future<ZebraPrinter> connectDescriptor(
    ZebraPrinterDescriptor descriptor, {
    Duration? timeout,
  }) async {
    final printer = register(descriptor);
    await printer.connect(timeout: timeout);
    return printer;
  }

  Future<void> disconnectAll() async {
    final printers = List<ZebraPrinter>.from(_printers.values);
    for (final printer in printers) {
      try {
        await printer.disconnect();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await disconnectAll();
    _printers.clear();
    _statuses.clear();
    for (final controller in _statusControllers.values) {
      await controller.close();
    }
    _statusControllers.clear();
    await _statusesController.close();
    await logger.close();
  }

  void _publishStatus(ZebraPrinterStatus status) {
    _statuses[status.printer.id] = status;
    if (!_statusesController.isClosed) {
      _statusesController.add(Map.unmodifiable(_statuses));
    }
    final controller = _statusControllers.putIfAbsent(
      status.printer.id,
      () => StreamController.broadcast(),
    );
    if (!controller.isClosed) {
      controller.add(status);
    }
  }
}
