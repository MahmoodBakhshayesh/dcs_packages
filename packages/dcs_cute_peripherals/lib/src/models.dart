enum CuteVendor { arinc, sita, resa }

enum CutePeripheralKind {
  atb,
  btp,
  bgr,
  bgr2,
  bgr3,
  bgr4,
  dcp,
  msr,
  ocr,
  lsr,
  lsr2,
  bcd,
  rte,
  bpp,
}

enum CutePeripheralState {
  disconnected,
  connecting,
  open,
  locked,
  failed,
}

class CutePeripheralEndpoint {
  const CutePeripheralEndpoint({
    required this.host,
    this.port = 50001,
  });

  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}

class CutePeripheralIdentity {
  const CutePeripheralIdentity({
    required this.kind,
    required this.name,
    this.order = 0,
    this.airlineCode = '',
  });

  final CutePeripheralKind kind;
  final String name;
  final int order;
  final String airlineCode;
}

class CutePeripheralStatus {
  const CutePeripheralStatus({
    required this.state,
    this.message = '',
    this.online = false,
    this.paperOk = true,
    this.locked = false,
    this.rawCode,
  });

  final CutePeripheralState state;
  final String message;
  final bool online;
  final bool paperOk;
  final bool locked;
  final int? rawCode;

  CutePeripheralStatus copyWith({
    CutePeripheralState? state,
    String? message,
    bool? online,
    bool? paperOk,
    bool? locked,
    int? rawCode,
  }) =>
      CutePeripheralStatus(
        state: state ?? this.state,
        message: message ?? this.message,
        online: online ?? this.online,
        paperOk: paperOk ?? this.paperOk,
        locked: locked ?? this.locked,
        rawCode: rawCode ?? this.rawCode,
      );

  @override
  String toString() =>
      'CutePeripheralStatus(${state.name}, online=$online, paperOk=$paperOk, locked=$locked, $message)';
}

class CutePeripheralFailure implements Exception {
  const CutePeripheralFailure(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => 'CutePeripheralFailure($message${code == null ? '' : ', code=$code'})';
}
