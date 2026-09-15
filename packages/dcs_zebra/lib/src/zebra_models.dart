enum ZebraConnectionType { tcp, bluetooth, bluetoothLe, usb }

enum ZebraPrinterRole { boardingPass, bagTag, generic }

enum ZebraPrinterState {
  unknown,
  discovered,
  connecting,
  connected,
  ready,
  busy,
  printing,
  degraded,
  disconnected,
  failed,
}

enum ZebraLogLevel { trace, debug, info, warning, error }

enum ZebraLogScope { client, device, transport, protocol, lifecycle }

enum ZebraMessageDirection { inbound, outbound, internal }

enum ZebraPrinterLanguage { zpl, cpcl, unknown }

class ZebraEndpoint {
  const ZebraEndpoint({
    required this.host,
    this.port = 9100,
    this.statusPort = 9200,
  });

  final String host;
  final int port;
  final int statusPort;

  @override
  String toString() => '$host:$port';
}

class ZebraPrinterDescriptor {
  const ZebraPrinterDescriptor({
    required this.id,
    required this.address,
    required this.connectionType,
    this.name = '',
    this.role = ZebraPrinterRole.generic,
    this.macAddress,
    this.serialNumber,
    this.model,
  });

  final String id;
  final String address;
  final ZebraConnectionType connectionType;
  final String name;
  final ZebraPrinterRole role;
  final String? macAddress;
  final String? serialNumber;
  final String? model;

  String get displayName =>
      name.trim().isNotEmpty ? name : '$connectionType:$address';

  ZebraPrinterDescriptor copyWith({
    String? id,
    String? address,
    ZebraConnectionType? connectionType,
    String? name,
    ZebraPrinterRole? role,
    String? macAddress,
    String? serialNumber,
    String? model,
  }) {
    return ZebraPrinterDescriptor(
      id: id ?? this.id,
      address: address ?? this.address,
      connectionType: connectionType ?? this.connectionType,
      name: name ?? this.name,
      role: role ?? this.role,
      macAddress: macAddress ?? this.macAddress,
      serialNumber: serialNumber ?? this.serialNumber,
      model: model ?? this.model,
    );
  }
}

class ZebraPrinterStatus {
  const ZebraPrinterStatus({
    required this.printer,
    required this.state,
    required this.message,
    this.connected = false,
    this.readyToPrint = false,
    this.printing = false,
    this.paperOut = false,
    this.headOpen = false,
    this.ribbonOut = false,
    this.paused = false,
    this.bufferFull = false,
    this.hardwareStatusLabel,
    this.language = ZebraPrinterLanguage.unknown,
    this.lastChangedAt,
    this.lastError,
  });

  factory ZebraPrinterStatus.discovered(ZebraPrinterDescriptor printer) {
    return ZebraPrinterStatus(
      printer: printer,
      state: ZebraPrinterState.discovered,
      message: 'Discovered',
      lastChangedAt: DateTime.now(),
    );
  }

  final ZebraPrinterDescriptor printer;
  final ZebraPrinterState state;
  final String message;
  final bool connected;
  final bool readyToPrint;
  final bool printing;
  final bool paperOut;
  final bool headOpen;
  final bool ribbonOut;
  final bool paused;
  final bool bufferFull;
  final String? hardwareStatusLabel;
  final ZebraPrinterLanguage language;
  final DateTime? lastChangedAt;
  final Object? lastError;

  bool get isUsable =>
      connected &&
      readyToPrint &&
      !paperOut &&
      !headOpen &&
      !paused &&
      state != ZebraPrinterState.failed;

  ZebraPrinterStatus copyWith({
    ZebraPrinterDescriptor? printer,
    ZebraPrinterState? state,
    String? message,
    bool? connected,
    bool? readyToPrint,
    bool? printing,
    bool? paperOut,
    bool? headOpen,
    bool? ribbonOut,
    bool? paused,
    bool? bufferFull,
    String? hardwareStatusLabel,
    ZebraPrinterLanguage? language,
    DateTime? lastChangedAt,
    Object? lastError,
    bool clearError = false,
    bool clearHardwareStatus = false,
  }) {
    return ZebraPrinterStatus(
      printer: printer ?? this.printer,
      state: state ?? this.state,
      message: message ?? this.message,
      connected: connected ?? this.connected,
      readyToPrint: readyToPrint ?? this.readyToPrint,
      printing: printing ?? this.printing,
      paperOut: paperOut ?? this.paperOut,
      headOpen: headOpen ?? this.headOpen,
      ribbonOut: ribbonOut ?? this.ribbonOut,
      paused: paused ?? this.paused,
      bufferFull: bufferFull ?? this.bufferFull,
      hardwareStatusLabel: clearHardwareStatus
          ? null
          : hardwareStatusLabel ?? this.hardwareStatusLabel,
      language: language ?? this.language,
      lastChangedAt: lastChangedAt ?? DateTime.now(),
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class ZebraCommandResult {
  const ZebraCommandResult({
    required this.ok,
    required this.result,
    this.message,
    this.response,
  });

  final bool ok;
  final String result;
  final String? message;
  final String? response;
}

class ZebraRequestFailure implements Exception {
  const ZebraRequestFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) return 'ZebraRequestFailure: $message';
    return 'ZebraRequestFailure: $message ($cause)';
  }
}

class ZebraConnectionOptions {
  const ZebraConnectionOptions({
    this.connectTimeout = const Duration(seconds: 10),
    this.writeTimeout = const Duration(seconds: 30),
    this.statusTimeout = const Duration(seconds: 5),
    this.autoQueryStatusAfterConnect = true,
    this.defaultTcpPort = 9100,
    this.defaultStatusPort = 9200,
  });

  final Duration connectTimeout;
  final Duration writeTimeout;
  final Duration statusTimeout;
  final bool autoQueryStatusAfterConnect;
  final int defaultTcpPort;
  final int defaultStatusPort;
}
