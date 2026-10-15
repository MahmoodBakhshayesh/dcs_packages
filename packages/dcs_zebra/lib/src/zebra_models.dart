enum ZebraConnectionType { tcp, bluetooth, bluetoothLe, usb, serial }

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
    this.manufacturer,
    this.rssi,
    this.paired = false,
  });

  factory ZebraPrinterDescriptor.fromMap(Map<Object?, Object?> map) {
    final typeName = (map['connectionType'] as String?) ?? 'tcp';
    final type = ZebraConnectionType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => ZebraConnectionType.tcp,
    );
    final address = (map['address'] as String?) ?? '';
    final id = (map['id'] as String?) ?? '${type.name}:$address';
    final rssiValue = map['rssi'];
    int? rssi;
    if (rssiValue is int) {
      rssi = rssiValue;
    } else if (rssiValue is num) {
      rssi = rssiValue.toInt();
    } else if (rssiValue is String) {
      rssi = int.tryParse(rssiValue);
    }
    return ZebraPrinterDescriptor(
      id: id,
      address: address,
      connectionType: type,
      name: (map['name'] as String?) ?? '',
      macAddress: map['macAddress'] as String?,
      serialNumber: map['serialNumber'] as String?,
      model: map['model'] as String?,
      manufacturer: map['manufacturer'] as String?,
      rssi: rssi,
      paired: map['paired'] == true,
    );
  }

  final String id;
  final String address;
  final ZebraConnectionType connectionType;
  final String name;
  final ZebraPrinterRole role;
  final String? macAddress;
  final String? serialNumber;
  final String? model;

  /// Windows SetupAPI / driver manufacturer (Zebra USB often reports `ZDesigner`).
  final String? manufacturer;

  /// Signal strength from BLE / Classic discovery when the platform provides it.
  final int? rssi;

  /// Whether the device is already bonded / paired with the host.
  final bool paired;

  /// Mobile Link-OS models: name/model prefix `ZQ`, `iMZ`, or `ZR`.
  bool get isMobileModel {
    final source = (model?.trim().isNotEmpty == true ? model! : name).trim();
    if (source.isEmpty) return false;
    final upper = source.toUpperCase();
    return upper.startsWith('ZQ') ||
        upper.startsWith('IMZ') ||
        upper.startsWith('ZR');
  }

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
    String? manufacturer,
    int? rssi,
    bool? paired,
    bool clearRssi = false,
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
      manufacturer: manufacturer ?? this.manufacturer,
      rssi: clearRssi ? null : rssi ?? this.rssi,
      paired: paired ?? this.paired,
    );
  }
}

/// Outcome of a Bluetooth pair / unpair request.
enum ZebraPairingResult {
  paired,
  unpaired,
  alreadyPaired,
  failed,
  /// iOS cannot initiate pairing in-app; open Settings / Bluetooth.
  openSystemSettings,
  unsupported,
}

/// Runtime Bluetooth permission state after [ZebraClient.ensureBluetoothPermissions].
enum ZebraPermissionState {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  unsupported,
}

/// One print job in a [ZebraPrinter.printBatch] sequence.
class ZebraJob {
  const ZebraJob({
    required this.id,
    required this.data,
    this.language = ZebraPrinterLanguage.zpl,
  });

  final String id;
  final String data;
  final ZebraPrinterLanguage language;
}

enum ZebraJobState { queued, sending, done, failed }

/// Per-job progress event from [ZebraPrinter.printBatch].
class ZebraJobProgress {
  const ZebraJobProgress({
    required this.jobId,
    required this.state,
    required this.index,
    required this.total,
    this.error,
  });

  final String jobId;
  final ZebraJobState state;
  final int index;
  final int total;
  final String? error;

  bool get isTerminal =>
      state == ZebraJobState.done || state == ZebraJobState.failed;
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
