import 'dart:convert';

/// CUPPS-aligned standalone device roles (exclude unknown).
enum DcsDeviceRole {
  boardingPassPrinter('bp', 'Boarding Pass Printer', DcsDeviceKind.printer),
  bagTagPrinter('bt', 'Bag Tag Printer', DcsDeviceKind.printer),
  barcodeReader('bc', 'Barcode Reader', DcsDeviceKind.reader),
  boardingGateReader('bg', 'Boarding Gate Reader', DcsDeviceKind.reader),
  passportReader('ms', 'Passport Reader (MSR)', DcsDeviceKind.reader),
  /// CUPPS `oc` — Optical Character Recognition (passport MRZ), same scan path as MSR.
  opticalCardReader('oc', 'Passport Reader (OCR)', DcsDeviceKind.reader),
  documentPrinter('pr', 'Document Printer (DCP)', DcsDeviceKind.printer),
  biometricReader('be', 'Biometric Reader', DcsDeviceKind.reader),
  displayDevice('dd', 'Display Device', DcsDeviceKind.unknown),
  zlDevice('zl', 'ZL Device', DcsDeviceKind.unknown),
  ziDevice('zi', 'ZI Device', DcsDeviceKind.unknown);

  const DcsDeviceRole(this.code, this.label, this.kind);

  final String code;
  final String label;
  final DcsDeviceKind kind;

  bool get isPrinter => kind == DcsDeviceKind.printer;
  bool get isReader => kind == DcsDeviceKind.reader;

  /// MSR + OCR both deliver passport / MRZ scans into the same bus.
  bool get isPassportReader =>
      this == DcsDeviceRole.passportReader ||
      this == DcsDeviceRole.opticalCardReader;

  static DcsDeviceRole? tryParse(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'ocr' || value == 'ocrreader') {
      return DcsDeviceRole.opticalCardReader;
    }
    if (value == 'msr' || value == 'msreader') {
      return DcsDeviceRole.passportReader;
    }
    if (value == 'dcp' || value == 'ltp' || value == 'lpt') {
      return DcsDeviceRole.documentPrinter;
    }
    for (final role in DcsDeviceRole.values) {
      if (role.name.toLowerCase() == value || role.code == value) return role;
    }
    return null;
  }

  static DcsDeviceRole fromCode(String code, {DcsDeviceRole fallback = DcsDeviceRole.barcodeReader}) {
    return tryParse(code) ?? fallback;
  }
}

/// Coarse functional role used by UI assets / legacy APIs.
enum DcsDeviceKind { reader, printer, unknown }

/// Physical or logical transport.
enum DcsDeviceTransport { serial, usb, network, parallel, unknown }

/// Connection mode selected in Standalone config UI.
enum DcsConnectionType { com, lan, lpt }

/// Print language / protocol for printer roles.
enum DcsPrintType { aea, zpl, stimulSoft, ePos }

/// Framing mode for request/response traffic.
enum DcsProtocolMode { none, framed, auto }

/// Current lifecycle state exposed to application UI.
enum DcsDeviceConnectionState {
  unconfigured,
  discovering,
  available,
  connecting,
  connected,
  retrying,
  degraded,
  disconnected,
  failed,
}

/// Optional logging level for package events.
enum DcsLogLevel { trace, debug, info, warning, error }

/// Standard serial flow-control / handshake options.
enum DcsSerialFlowControl { none, xonXoff, rtsCts, dtrDsr, requestToSend, requestToSendXonXoff }

/// Serial port options used when connecting to COM/TTY devices.
class DcsSerialOptions {
  const DcsSerialOptions({
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
    this.flowControl = DcsSerialFlowControl.none,
    this.dtrEnable = true,
    this.rtsEnable = true,
    this.receivedBytesThreshold = 1,
    this.protocolMode = DcsProtocolMode.auto,
    this.readTimeout = const Duration(milliseconds: 8000),
    this.writeTimeout = const Duration(milliseconds: 8000),
  });

  final int baudRate;
  final int dataBits;
  final int stopBits;

  /// libserialport parity value. `0` is none.
  final int parity;
  final DcsSerialFlowControl flowControl;
  final bool dtrEnable;
  final bool rtsEnable;
  final int receivedBytesThreshold;
  final DcsProtocolMode protocolMode;
  final Duration readTimeout;
  final Duration writeTimeout;

  bool get framed =>
      protocolMode == DcsProtocolMode.framed || protocolMode == DcsProtocolMode.auto;

  DcsSerialOptions copyWith({
    int? baudRate,
    int? dataBits,
    int? stopBits,
    int? parity,
    DcsSerialFlowControl? flowControl,
    bool? dtrEnable,
    bool? rtsEnable,
    int? receivedBytesThreshold,
    DcsProtocolMode? protocolMode,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) {
    return DcsSerialOptions(
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      stopBits: stopBits ?? this.stopBits,
      parity: parity ?? this.parity,
      flowControl: flowControl ?? this.flowControl,
      dtrEnable: dtrEnable ?? this.dtrEnable,
      rtsEnable: rtsEnable ?? this.rtsEnable,
      receivedBytesThreshold: receivedBytesThreshold ?? this.receivedBytesThreshold,
      protocolMode: protocolMode ?? this.protocolMode,
      readTimeout: readTimeout ?? this.readTimeout,
      writeTimeout: writeTimeout ?? this.writeTimeout,
    );
  }

  Map<String, Object?> toJson() => {
        'baudRate': baudRate,
        'dataBits': dataBits,
        'stopBits': stopBits,
        'parity': parity,
        'flowControl': flowControl.name,
        'dtrEnable': dtrEnable,
        'rtsEnable': rtsEnable,
        'receivedBytesThreshold': receivedBytesThreshold,
        'protocolMode': protocolMode.name,
        'readTimeoutMs': readTimeout.inMilliseconds,
        'writeTimeoutMs': writeTimeout.inMilliseconds,
      };

  factory DcsSerialOptions.fromJson(Map<String, Object?> json) {
    return DcsSerialOptions(
      baudRate: _int(json['baudRate'], 115200),
      dataBits: _int(json['dataBits'], 8),
      stopBits: _int(json['stopBits'], 1),
      parity: _int(json['parity'], 0),
      flowControl: _enumValue(
        DcsSerialFlowControl.values,
        json['flowControl'] as String?,
        DcsSerialFlowControl.none,
      ),
      dtrEnable: json['dtrEnable'] as bool? ?? true,
      rtsEnable: json['rtsEnable'] as bool? ?? true,
      receivedBytesThreshold: _int(json['receivedBytesThreshold'], 1),
      protocolMode: _enumValue(
        DcsProtocolMode.values,
        json['protocolMode'] as String?,
        DcsProtocolMode.auto,
      ),
      readTimeout: Duration(milliseconds: _int(json['readTimeoutMs'], 8000)),
      writeTimeout: Duration(milliseconds: _int(json['writeTimeoutMs'], 8000)),
    );
  }
}

/// Printer-only extras from Standalone BP/BT config UI.
class DcsPrinterOptions {
  const DcsPrinterOptions({
    this.printType = DcsPrintType.aea,
    this.autoBin = false,
    this.logoBinary = false,
    this.resetBin = false,
  });

  final DcsPrintType printType;
  final bool autoBin;
  final bool logoBinary;
  final bool resetBin;

  DcsPrinterOptions copyWith({
    DcsPrintType? printType,
    bool? autoBin,
    bool? logoBinary,
    bool? resetBin,
  }) {
    return DcsPrinterOptions(
      printType: printType ?? this.printType,
      autoBin: autoBin ?? this.autoBin,
      logoBinary: logoBinary ?? this.logoBinary,
      resetBin: resetBin ?? this.resetBin,
    );
  }

  Map<String, Object?> toJson() => {
        'printType': printType.name,
        'autoBin': autoBin,
        'logoBinary': logoBinary,
        'resetBin': resetBin,
      };

  factory DcsPrinterOptions.fromJson(Map<String, Object?> json) {
    return DcsPrinterOptions(
      printType: _enumValue(
        DcsPrintType.values,
        json['printType'] as String?,
        DcsPrintType.aea,
      ),
      autoBin: json['autoBin'] as bool? ?? false,
      logoBinary: json['logoBinary'] as bool? ?? false,
      resetBin: json['resetBin'] as bool? ?? false,
    );
  }
}

/// LAN endpoint when [DcsConnectionType.lan] is selected.
class DcsLanEndpoint {
  const DcsLanEndpoint({this.host = '', this.port = 0});

  final String host;
  final int port;

  bool get isConfigured => host.trim().isNotEmpty && port > 0;

  DcsLanEndpoint copyWith({String? host, int? port}) => DcsLanEndpoint(
        host: host ?? this.host,
        port: port ?? this.port,
      );

  Map<String, Object?> toJson() => {'host': host, 'port': port};

  factory DcsLanEndpoint.fromJson(Map<String, Object?> json) => DcsLanEndpoint(
        host: json['host'] as String? ?? '',
        port: _int(json['port'], 0),
      );
}

/// Matching rules used to recognize a reader or printer from discovered ports.
class DcsDeviceMatcher {
  const DcsDeviceMatcher({
    this.portName,
    this.manufacturer,
    this.productName,
    this.serialNumber,
    this.vendorId,
    this.productId,
    this.metadata = const {},
  });

  final Pattern? portName;
  final Pattern? manufacturer;
  final Pattern? productName;
  final Pattern? serialNumber;
  final int? vendorId;
  final int? productId;
  final Map<String, String> metadata;

  bool matches(DcsDiscoveredDevice device) {
    if (!_matchesPortName(portName, device.portName)) return false;
    if (!_matchesPattern(manufacturer, device.manufacturer)) return false;
    if (!_matchesPattern(productName, device.productName)) return false;
    if (!_matchesPattern(serialNumber, device.serialNumber)) return false;
    if (vendorId != null && vendorId != device.vendorId) return false;
    if (productId != null && productId != device.productId) return false;

    for (final entry in metadata.entries) {
      if (device.metadata[entry.key] != entry.value) return false;
    }

    return true;
  }

  DcsDeviceMatcher copyWith({
    Pattern? portName,
    Pattern? manufacturer,
    Pattern? productName,
    Pattern? serialNumber,
    int? vendorId,
    int? productId,
    Map<String, String>? metadata,
  }) {
    return DcsDeviceMatcher(
      portName: portName ?? this.portName,
      manufacturer: manufacturer ?? this.manufacturer,
      productName: productName ?? this.productName,
      serialNumber: serialNumber ?? this.serialNumber,
      vendorId: vendorId ?? this.vendorId,
      productId: productId ?? this.productId,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() => {
        'portName': _patternToJson(portName),
        'manufacturer': _patternToJson(manufacturer),
        'productName': _patternToJson(productName),
        'serialNumber': _patternToJson(serialNumber),
        'vendorId': vendorId,
        'productId': productId,
        'metadata': metadata,
      };

  factory DcsDeviceMatcher.fromJson(Map<String, Object?> json) {
    return DcsDeviceMatcher(
      portName: _patternFromJson(json['portName']),
      manufacturer: _patternFromJson(json['manufacturer']),
      productName: _patternFromJson(json['productName']),
      serialNumber: _patternFromJson(json['serialNumber']),
      vendorId: _nullableInt(json['vendorId']),
      productId: _nullableInt(json['productId']),
      metadata: _stringMap(json['metadata']),
    );
  }
}

/// A configured device profile saved by the application.
class DcsDeviceProfile {
  DcsDeviceProfile({
    required this.id,
    required this.label,
    required this.role,
    DcsDeviceKind? kind,
    this.transport = DcsDeviceTransport.serial,
    this.connectionType = DcsConnectionType.com,
    this.matcher = const DcsDeviceMatcher(),
    this.serialOptions = const DcsSerialOptions(),
    this.printerOptions = const DcsPrinterOptions(),
    this.lan = const DcsLanEndpoint(),
    this.enabled = false,
    this.metadata = const {},
  }) : kind = kind ?? role.kind;

  final String id;
  final String label;
  final DcsDeviceRole role;
  final DcsDeviceKind kind;
  final DcsDeviceTransport transport;
  final DcsConnectionType connectionType;
  final DcsDeviceMatcher matcher;
  final DcsSerialOptions serialOptions;
  final DcsPrinterOptions printerOptions;
  final DcsLanEndpoint lan;
  final bool enabled;
  final Map<String, String> metadata;

  String? get comPort {
    final p = matcher.portName;
    if (p is String) return p;
    return p?.toString();
  }

  DcsDeviceProfile copyWith({
    String? id,
    String? label,
    DcsDeviceRole? role,
    DcsDeviceKind? kind,
    DcsDeviceTransport? transport,
    DcsConnectionType? connectionType,
    DcsDeviceMatcher? matcher,
    DcsSerialOptions? serialOptions,
    DcsPrinterOptions? printerOptions,
    DcsLanEndpoint? lan,
    bool? enabled,
    Map<String, String>? metadata,
  }) {
    final nextRole = role ?? this.role;
    return DcsDeviceProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      role: nextRole,
      kind: kind ?? (role != null ? nextRole.kind : this.kind),
      transport: transport ?? this.transport,
      connectionType: connectionType ?? this.connectionType,
      matcher: matcher ?? this.matcher,
      serialOptions: serialOptions ?? this.serialOptions,
      printerOptions: printerOptions ?? this.printerOptions,
      lan: lan ?? this.lan,
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'role': role.name,
        'kind': kind.name,
        'transport': transport.name,
        'connectionType': connectionType.name,
        'matcher': matcher.toJson(),
        'serialOptions': serialOptions.toJson(),
        'printerOptions': printerOptions.toJson(),
        'lan': lan.toJson(),
        'enabled': enabled,
        'metadata': metadata,
      };

  factory DcsDeviceProfile.fromJson(Map<String, Object?> json) {
    final role = DcsDeviceRole.tryParse(json['role'] as String?) ??
        _roleFromLegacyKind(
          _enumValue(DcsDeviceKind.values, json['kind'] as String?, DcsDeviceKind.unknown),
          json['id'] as String? ?? '',
        );
    return DcsDeviceProfile(
      id: json['id'] as String,
      label: json['label'] as String? ?? role.label,
      role: role,
      kind: _enumValue(DcsDeviceKind.values, json['kind'] as String?, role.kind),
      transport: _enumValue(
        DcsDeviceTransport.values,
        json['transport'] as String?,
        DcsDeviceTransport.serial,
      ),
      connectionType: _enumValue(
        DcsConnectionType.values,
        json['connectionType'] as String?,
        DcsConnectionType.com,
      ),
      matcher: DcsDeviceMatcher.fromJson(_objectMap(json['matcher'])),
      serialOptions: DcsSerialOptions.fromJson(_objectMap(json['serialOptions'])),
      printerOptions: DcsPrinterOptions.fromJson(_objectMap(json['printerOptions'])),
      lan: DcsLanEndpoint.fromJson(_objectMap(json['lan'])),
      enabled: json['enabled'] as bool? ?? false,
      metadata: _stringMap(json['metadata']),
    );
  }
}

DcsDeviceRole _roleFromLegacyKind(DcsDeviceKind kind, String id) {
  final lower = id.toLowerCase();
  if (lower.contains('bp') || lower.contains('boarding')) {
    return DcsDeviceRole.boardingPassPrinter;
  }
  if (lower.contains('bt') || lower.contains('bag')) {
    return DcsDeviceRole.bagTagPrinter;
  }
  if (lower.contains('bg') || lower.contains('gate')) {
    return DcsDeviceRole.boardingGateReader;
  }
  if (lower.contains('ms') ||
      lower.contains('msr') ||
      lower.contains('passport')) {
    return DcsDeviceRole.passportReader;
  }
  if (lower.contains('pr') ||
      lower.contains('dcp') ||
      lower.contains('document') ||
      lower.contains('ltp') ||
      lower.contains('lpt')) {
    return DcsDeviceRole.documentPrinter;
  }
  if (lower == 'oc' ||
      lower.contains('ocr') ||
      lower.contains('optical')) {
    return DcsDeviceRole.opticalCardReader;
  }
  return switch (kind) {
    DcsDeviceKind.printer => DcsDeviceRole.boardingPassPrinter,
    DcsDeviceKind.reader => DcsDeviceRole.barcodeReader,
    DcsDeviceKind.unknown => DcsDeviceRole.displayDevice,
  };
}

/// A device or port found during discovery.
class DcsDiscoveredDevice {
  const DcsDiscoveredDevice({
    required this.id,
    required this.portName,
    required this.transport,
    this.manufacturer,
    this.productName,
    this.serialNumber,
    this.vendorId,
    this.productId,
    this.metadata = const {},
  });

  final String id;
  final String portName;
  final DcsDeviceTransport transport;
  final String? manufacturer;
  final String? productName;
  final String? serialNumber;
  final int? vendorId;
  final int? productId;
  final Map<String, String> metadata;

  Map<String, Object?> toJson() => {
        'id': id,
        'portName': portName,
        'transport': transport.name,
        'manufacturer': manufacturer,
        'productName': productName,
        'serialNumber': serialNumber,
        'vendorId': vendorId,
        'productId': productId,
        'metadata': metadata,
      };
}

/// Retry policy for connect and reconnect attempts.
class DcsRetryPolicy {
  const DcsRetryPolicy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(milliseconds: 300),
    this.maxDelay = const Duration(seconds: 8),
    this.backoffFactor = 1.8,
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffFactor;

  Duration delayForAttempt(int attempt) {
    final multiplier = _pow(backoffFactor, attempt - 1);
    final ms = (initialDelay.inMilliseconds * multiplier).round();
    return Duration(milliseconds: ms.clamp(0, maxDelay.inMilliseconds));
  }
}

/// Heartbeat settings used to verify an open connection stays alive.
class DcsConnectionHealthPolicy {
  const DcsConnectionHealthPolicy({
    this.heartbeatInterval = const Duration(seconds: 5),
    this.maxMissedHeartbeats = 2,
  }) : assert(maxMissedHeartbeats >= 0);

  final Duration heartbeatInterval;
  final int maxMissedHeartbeats;
}

/// Persisted package configuration.
class DcsDeviceConfig {
  const DcsDeviceConfig({
    this.profiles = const [],
    this.autoReconnect = true,
    this.discoveryInterval = const Duration(seconds: 5),
  });

  final List<DcsDeviceProfile> profiles;
  final bool autoReconnect;
  final Duration discoveryInterval;

  /// Default Standalone catalog: one profile per CUPPS role (disabled until configured).
  factory DcsDeviceConfig.cuppsDefaults() {
    return DcsDeviceConfig(
      profiles: [
        for (final role in DcsDeviceRole.values)
          DcsDeviceProfile(
            id: role.code,
            label: role.label,
            role: role,
            enabled: false,
          ),
      ],
    );
  }

  /// Merge saved profiles onto CUPPS defaults so new roles appear after upgrades.
  DcsDeviceConfig withCuppsCatalogEnsured() {
    final byId = {for (final p in profiles) p.id: p};
    final merged = <DcsDeviceProfile>[
      for (final role in DcsDeviceRole.values)
        (byId[role.code] ??
                DcsDeviceProfile(
                  id: role.code,
                  label: role.label,
                  role: role,
                  enabled: false,
                ))
            .copyWith(label: role.label, role: role),
    ];
    // Keep any custom/extra profiles not in the catalog.
    for (final p in profiles) {
      if (!merged.any((m) => m.id == p.id)) merged.add(p);
    }
    return copyWith(profiles: merged);
  }

  DcsDeviceConfig copyWith({
    List<DcsDeviceProfile>? profiles,
    bool? autoReconnect,
    Duration? discoveryInterval,
  }) {
    return DcsDeviceConfig(
      profiles: profiles ?? this.profiles,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      discoveryInterval: discoveryInterval ?? this.discoveryInterval,
    );
  }

  Map<String, Object?> toJson() => {
        'profiles': profiles.map((profile) => profile.toJson()).toList(),
        'autoReconnect': autoReconnect,
        'discoveryIntervalMs': discoveryInterval.inMilliseconds,
      };

  String encode() => jsonEncode(toJson());

  factory DcsDeviceConfig.fromJson(Map<String, Object?> json) {
    return DcsDeviceConfig(
      profiles: (json['profiles'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (profile) => DcsDeviceProfile.fromJson(Map<String, Object?>.from(profile)),
          )
          .toList(growable: false),
      autoReconnect: json['autoReconnect'] as bool? ?? true,
      discoveryInterval: Duration(
        milliseconds: _int(json['discoveryIntervalMs'], 5000),
      ),
    ).withCuppsCatalogEnsured();
  }

  factory DcsDeviceConfig.decode(String value) {
    return DcsDeviceConfig.fromJson(
      Map<String, Object?>.from(jsonDecode(value) as Map),
    );
  }
}

/// UI-facing status for one configured profile.
class DcsDeviceStatus {
  const DcsDeviceStatus({
    required this.profileId,
    required this.state,
    required this.updatedAt,
    this.message,
    this.attempt = 0,
    this.device,
    this.error,
  });

  factory DcsDeviceStatus.initial(String profileId) {
    return DcsDeviceStatus(
      profileId: profileId,
      state: DcsDeviceConnectionState.unconfigured,
      updatedAt: DateTime.now(),
    );
  }

  final String profileId;
  final DcsDeviceConnectionState state;
  final DateTime updatedAt;
  final String? message;
  final int attempt;
  final DcsDiscoveredDevice? device;
  final Object? error;

  bool get isConnected => state == DcsDeviceConnectionState.connected;
  bool get needsAttention =>
      state == DcsDeviceConnectionState.failed ||
      state == DcsDeviceConnectionState.degraded ||
      state == DcsDeviceConnectionState.disconnected;

  DcsDeviceStatus copyWith({
    DcsDeviceConnectionState? state,
    DateTime? updatedAt,
    String? message,
    int? attempt,
    DcsDiscoveredDevice? device,
    Object? error,
    bool clearError = false,
  }) {
    return DcsDeviceStatus(
      profileId: profileId,
      state: state ?? this.state,
      updatedAt: updatedAt ?? DateTime.now(),
      message: message ?? this.message,
      attempt: attempt ?? this.attempt,
      device: device ?? this.device,
      error: clearError ? null : error ?? this.error,
    );
  }
}

/// Structured log event. Logging is disabled when no sink is supplied.
class DcsLogEvent {
  const DcsLogEvent({
    required this.level,
    required this.message,
    required this.timestamp,
    this.profileId,
    this.error,
    this.stackTrace,
    this.data = const {},
  });

  final DcsLogLevel level;
  final String message;
  final DateTime timestamp;
  final String? profileId;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> data;
}

typedef DcsLogger = void Function(DcsLogEvent event);

/// Common baud rates for Standalone COM UI.
const List<int> kDcsBaudRates = [
  75,
  110,
  134,
  150,
  300,
  600,
  1200,
  1800,
  2400,
  4800,
  7200,
  9600,
  14400,
  19200,
  28800,
  38400,
  57600,
  115200,
  128000,
];

/// Common data-bit choices for Standalone COM UI.
const List<int> kDcsDataBits = [4, 5, 6, 7, 8];

bool _matchesPattern(Pattern? pattern, String? value) {
  if (pattern == null) return true;
  if (value == null) return false;
  return pattern.allMatches(value).isNotEmpty;
}

/// COM/LPT port names must be exact (case-insensitive).
///
/// Substring [Pattern] matching would let configured `COM4` incorrectly bind to
/// `COM44` / `COM40` when those ports appear in discovery.
bool _matchesPortName(Pattern? pattern, String? value) {
  if (pattern == null) return true;
  if (value == null) return false;
  if (pattern is String) {
    return pattern.trim().toUpperCase() == value.trim().toUpperCase();
  }
  if (pattern is RegExp) {
    final match = pattern.firstMatch(value);
    return match != null && match.start == 0 && match.end == value.length;
  }
  final match = pattern.matchAsPrefix(value);
  return match != null && match.end == value.length;
}

Map<String, Object?> _patternToJson(Pattern? pattern) {
  if (pattern == null) return const {};
  if (pattern is RegExp) {
    return {
      'type': 'regexp',
      'value': pattern.pattern,
      'caseSensitive': pattern.isCaseSensitive,
      'multiLine': pattern.isMultiLine,
      'unicode': pattern.isUnicode,
      'dotAll': pattern.isDotAll,
    };
  }
  return {'type': 'string', 'value': pattern.toString()};
}

Pattern? _patternFromJson(Object? value) {
  final json = _objectMap(value);
  if (json.isEmpty) return null;

  final pattern = json['value'] as String?;
  if (pattern == null || pattern.isEmpty) return null;

  if (json['type'] == 'regexp') {
    return RegExp(
      pattern,
      caseSensitive: json['caseSensitive'] as bool? ?? true,
      multiLine: json['multiLine'] as bool? ?? false,
      unicode: json['unicode'] as bool? ?? false,
      dotAll: json['dotAll'] as bool? ?? false,
    );
  }

  return pattern;
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map) return Map<String, Object?>.from(value);
  return const {};
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}

int _int(Object? value, int fallback) => _nullableInt(value) ?? fallback;

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

T _enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  final normalized = name.trim().toLowerCase();
  for (final value in values) {
    if (value.name.toLowerCase() == normalized) return value;
  }
  return fallback;
}

double _pow(double base, int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i += 1) {
    result *= base;
  }
  return result;
}
