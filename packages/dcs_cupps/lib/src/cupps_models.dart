import 'dart:async';

enum CuppsPlatformState {
  idle,
  connecting,
  connected,
  authenticating,
  authenticated,
  discoveringDevices,
  ready,
  degraded,
  disconnecting,
  disconnected,
  failed,
}

enum CuppsDeviceState {
  unknown,
  discovered,
  connecting,
  connected,
  initializing,
  initialized,
  acquiring,
  acquired,
  locking,
  locked,
  busy,
  dataAvailable,
  degraded,
  disconnected,
  failed,
}

enum CuppsDeviceType {
  boardingPassPrinter('bp', 'bpDeviceParameter'),
  bagTagPrinter('bt', 'btDeviceParameter'),
  barcodeReader('bc', 'bcDeviceParameter'),
  boardingGateReader('bg', 'bgDeviceParameter'),
  passportReader('ms', 'msDeviceParameter'),
  opticalCardReader('oc', 'ocDeviceParameter'),
  documentPrinter('pr', 'prDeviceParameter'),
  biometricReader('be', 'beDeviceParameter'),
  displayDevice('dd', 'ddDeviceParameter'),
  zlDevice('zl', 'zlDeviceParameter'),
  ziDevice('zi', 'ziDeviceParameter'),
  unknown('unknown', '');

  const CuppsDeviceType(this.code, this.parameterName);

  final String code;
  final String parameterName;

  static CuppsDeviceType fromParameterName(String? value) {
    return CuppsDeviceType.values.firstWhere(
      (type) => type.parameterName == value,
      orElse: () => CuppsDeviceType.unknown,
    );
  }
}

enum CuppsLogLevel { trace, debug, info, warning, error }

enum CuppsLogScope { platform, device, protocol, socket, lifecycle }

enum CuppsMessageDirection { inbound, outbound, internal }

class CuppsConnectionOptions {
  const CuppsConnectionOptions({
    this.connectTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 12),
    this.heartbeatInterval = const Duration(seconds: 45),
    this.heartbeatTimeout = const Duration(seconds: 12),
    this.interfaceLevel = '01.03',
    this.hsXsdVersion = '01.01.0128',
    this.autoReconnect = true,
    this.requiredDeviceTypes = const {
      CuppsDeviceType.boardingPassPrinter,
      CuppsDeviceType.bagTagPrinter,
      CuppsDeviceType.barcodeReader,
      CuppsDeviceType.boardingGateReader,
      CuppsDeviceType.passportReader,
      CuppsDeviceType.opticalCardReader,
      CuppsDeviceType.documentPrinter,
      CuppsDeviceType.biometricReader,
      CuppsDeviceType.displayDevice,
      CuppsDeviceType.zlDevice,
      CuppsDeviceType.ziDevice,
    },
  });

  final Duration connectTimeout;
  final Duration requestTimeout;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final String interfaceLevel;
  final String hsXsdVersion;
  final bool autoReconnect;
  final Set<CuppsDeviceType> requiredDeviceTypes;
}

class CuppsApplicationInfo {
  const CuppsApplicationInfo({
    required this.airlineCode,
    required this.applicationName,
    required this.applicationVersion,
    this.applicationData,
  });

  final String airlineCode;
  final String applicationName;
  final String applicationVersion;
  final String? applicationData;
}

class CuppsEndpoint {
  const CuppsEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}

class CuppsPlatformStatus {
  const CuppsPlatformStatus({
    required this.state,
    required this.message,
    this.endpoint,
    this.authenticated = false,
    this.interfaceLevel,
    this.lastChangedAt,
    this.lastError,
  });

  const CuppsPlatformStatus.idle()
    : state = CuppsPlatformState.idle,
      message = 'Idle',
      endpoint = null,
      authenticated = false,
      interfaceLevel = null,
      lastChangedAt = null,
      lastError = null;

  final CuppsPlatformState state;
  final String message;
  final CuppsEndpoint? endpoint;
  final bool authenticated;
  final String? interfaceLevel;
  final DateTime? lastChangedAt;
  final Object? lastError;

  CuppsPlatformStatus copyWith({
    CuppsPlatformState? state,
    String? message,
    CuppsEndpoint? endpoint,
    bool? authenticated,
    String? interfaceLevel,
    DateTime? lastChangedAt,
    Object? lastError,
    bool clearError = false,
  }) {
    return CuppsPlatformStatus(
      state: state ?? this.state,
      message: message ?? this.message,
      endpoint: endpoint ?? this.endpoint,
      authenticated: authenticated ?? this.authenticated,
      interfaceLevel: interfaceLevel ?? this.interfaceLevel,
      lastChangedAt: lastChangedAt ?? DateTime.now(),
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class CuppsDeviceDescriptor {
  const CuppsDeviceDescriptor({
    required this.index,
    required this.name,
    required this.parameterType,
    required this.type,
    required this.ip,
    required this.port,
    this.supportedInterfaceModes = const [],
    this.rawXml,
  });

  final String index;
  final String name;
  final String parameterType;
  final CuppsDeviceType type;
  final String ip;
  final int port;
  final List<String> supportedInterfaceModes;
  final String? rawXml;

  String get id => '$index:$name';
  CuppsEndpoint get endpoint => CuppsEndpoint(host: ip, port: port);
}

class CuppsDeviceStatus {
  const CuppsDeviceStatus({
    required this.device,
    required this.state,
    required this.message,
    this.locked = false,
    this.acquired = false,
    this.initialized = false,
    this.lastChangedAt,
    this.lastError,
  });

  final CuppsDeviceDescriptor device;
  final CuppsDeviceState state;
  final String message;
  final bool locked;
  final bool acquired;
  final bool initialized;
  final DateTime? lastChangedAt;
  final Object? lastError;

  CuppsDeviceStatus copyWith({
    CuppsDeviceState? state,
    String? message,
    bool? locked,
    bool? acquired,
    bool? initialized,
    DateTime? lastChangedAt,
    Object? lastError,
    bool clearError = false,
  }) {
    return CuppsDeviceStatus(
      device: device,
      state: state ?? this.state,
      message: message ?? this.message,
      locked: locked ?? this.locked,
      acquired: acquired ?? this.acquired,
      initialized: initialized ?? this.initialized,
      lastChangedAt: lastChangedAt ?? DateTime.now(),
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class CuppsCommandResult {
  const CuppsCommandResult({
    required this.ok,
    required this.result,
    required this.rawXml,
    this.message,
  });

  final bool ok;
  final String result;
  final String rawXml;
  final String? message;
}

class CuppsRequestFailure implements Exception {
  const CuppsRequestFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) return 'CuppsRequestFailure: $message';
    return 'CuppsRequestFailure: $message ($cause)';
  }
}

typedef CuppsStopCommandHandler =
    FutureOr<CuppsStopCommandDecision> Function(CuppsStopCommand command);

class CuppsStopCommand {
  const CuppsStopCommand({required this.canDefer, required this.message});

  final bool canDefer;
  final String message;
}

enum CuppsStopCommandDecision { defer, forceClose }
