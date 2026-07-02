import 'dart:convert';

/// The functional role of a DCS device.
enum DcsDeviceKind { reader, printer, unknown }

/// The physical or logical transport used by a device.
enum DcsDeviceTransport { serial, usb, network, unknown }

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

/// Standard serial flow-control options.
enum DcsSerialFlowControl { none, xonXoff, rtsCts, dtrDsr }

/// Serial port options used when connecting to COM/TTY devices.
class DcsSerialOptions {
  const DcsSerialOptions({
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
    this.flowControl = DcsSerialFlowControl.none,
    this.readTimeout = const Duration(milliseconds: 500),
    this.writeTimeout = const Duration(seconds: 2),
  });

  final int baudRate;
  final int dataBits;
  final int stopBits;

  /// libserialport parity value. `0` is none.
  final int parity;
  final DcsSerialFlowControl flowControl;
  final Duration readTimeout;
  final Duration writeTimeout;

  DcsSerialOptions copyWith({
    int? baudRate,
    int? dataBits,
    int? stopBits,
    int? parity,
    DcsSerialFlowControl? flowControl,
    Duration? readTimeout,
    Duration? writeTimeout,
  }) {
    return DcsSerialOptions(
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      stopBits: stopBits ?? this.stopBits,
      parity: parity ?? this.parity,
      flowControl: flowControl ?? this.flowControl,
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
    'readTimeoutMs': readTimeout.inMilliseconds,
    'writeTimeoutMs': writeTimeout.inMilliseconds,
  };

  factory DcsSerialOptions.fromJson(Map<String, Object?> json) {
    return DcsSerialOptions(
      baudRate: _int(json['baudRate'], 9600),
      dataBits: _int(json['dataBits'], 8),
      stopBits: _int(json['stopBits'], 1),
      parity: _int(json['parity'], 0),
      flowControl: _enumValue(
        DcsSerialFlowControl.values,
        json['flowControl'] as String?,
        DcsSerialFlowControl.none,
      ),
      readTimeout: Duration(milliseconds: _int(json['readTimeoutMs'], 500)),
      writeTimeout: Duration(milliseconds: _int(json['writeTimeoutMs'], 2000)),
    );
  }
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
    if (!_matchesPattern(portName, device.portName)) return false;
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
  const DcsDeviceProfile({
    required this.id,
    required this.label,
    required this.kind,
    this.transport = DcsDeviceTransport.serial,
    this.matcher = const DcsDeviceMatcher(),
    this.serialOptions = const DcsSerialOptions(),
    this.enabled = true,
    this.metadata = const {},
  });

  final String id;
  final String label;
  final DcsDeviceKind kind;
  final DcsDeviceTransport transport;
  final DcsDeviceMatcher matcher;
  final DcsSerialOptions serialOptions;
  final bool enabled;
  final Map<String, String> metadata;

  DcsDeviceProfile copyWith({
    String? id,
    String? label,
    DcsDeviceKind? kind,
    DcsDeviceTransport? transport,
    DcsDeviceMatcher? matcher,
    DcsSerialOptions? serialOptions,
    bool? enabled,
    Map<String, String>? metadata,
  }) {
    return DcsDeviceProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      transport: transport ?? this.transport,
      matcher: matcher ?? this.matcher,
      serialOptions: serialOptions ?? this.serialOptions,
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'transport': transport.name,
    'matcher': matcher.toJson(),
    'serialOptions': serialOptions.toJson(),
    'enabled': enabled,
    'metadata': metadata,
  };

  factory DcsDeviceProfile.fromJson(Map<String, Object?> json) {
    return DcsDeviceProfile(
      id: json['id'] as String,
      label: json['label'] as String,
      kind: _enumValue(
        DcsDeviceKind.values,
        json['kind'] as String?,
        DcsDeviceKind.unknown,
      ),
      transport: _enumValue(
        DcsDeviceTransport.values,
        json['transport'] as String?,
        DcsDeviceTransport.serial,
      ),
      matcher: DcsDeviceMatcher.fromJson(_objectMap(json['matcher'])),
      serialOptions: DcsSerialOptions.fromJson(
        _objectMap(json['serialOptions']),
      ),
      enabled: json['enabled'] as bool? ?? true,
      metadata: _stringMap(json['metadata']),
    );
  }
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
            (profile) =>
                DcsDeviceProfile.fromJson(Map<String, Object?>.from(profile)),
          )
          .toList(growable: false),
      autoReconnect: json['autoReconnect'] as bool? ?? true,
      discoveryInterval: Duration(
        milliseconds: _int(json['discoveryIntervalMs'], 5000),
      ),
    );
  }

  factory DcsDeviceConfig.decode(String value) {
    return DcsDeviceConfig.fromJson(jsonDecode(value) as Map<String, Object?>);
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

bool _matchesPattern(Pattern? pattern, String? value) {
  if (pattern == null) return true;
  if (value == null) return false;
  return pattern.allMatches(value).isNotEmpty;
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
  for (final value in values) {
    if (value.name == name) return value;
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
