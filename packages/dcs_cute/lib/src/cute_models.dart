import 'dart:typed_data';

enum CuteTrafficType {
  typeA(350),
  typeB(351);

  const CuteTrafficType(this.defaultPort);

  final int defaultPort;
}

enum CuteTrafficSubtype {
  conversational(0x01),
  iataHostToHost(0x02),
  sitaHostToHost(0x08);

  const CuteTrafficSubtype(this.code);

  final int code;
}

enum CuteCharacterSet {
  baudot5Bit(0x00),
  ipars6Bit(0x02),
  ascii7Bit(0x04),
  ebcdic8Bit(0x06);

  const CuteCharacterSet(this.code);

  final int code;
}

enum CuteMultiplexMode {
  groupWithFourByteAscu(0x00),
  groupWithTwoByteAscu(0x01),
  singleAscu(0x02);

  const CuteMultiplexMode(this.code);

  final int code;
}

enum CuteAddressHeader {
  full(0x00),
  partial(0x01),
  none(0x02);

  const CuteAddressHeader(this.code);

  final int code;
}

enum CutePresentation {
  p1024b(0x01),
  p1024c(0x02),
  terminal3270(0x03);

  const CutePresentation(this.code);

  final int code;
}

enum CuteSessionState {
  idle,
  connecting,
  tcpConnected,
  openingSession,
  open,
  closing,
  closed,
  failed,
}

enum CuteMatipCommand {
  data(0x00),
  sessionOpen(0x7e),
  openConfirm(0x7d),
  sessionClose(0x7c);

  const CuteMatipCommand(this.code);

  final int code;

  static CuteMatipCommand fromHeader({
    required bool control,
    required int code,
  }) {
    if (!control) return CuteMatipCommand.data;
    return CuteMatipCommand.values.firstWhere(
      (command) => command.code == code,
      orElse: () => throw CuteProtocolFailure('Unknown MATIP command: $code.'),
    );
  }
}

class CuteEndpoint {
  const CuteEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}

class CuteAscuAddress {
  const CuteAscuAddress({
    this.h1 = 0,
    this.h2 = 0,
    required this.a1,
    required this.a2,
  });

  final int h1;
  final int h2;
  final int a1;
  final int a2;

  Uint8List toFourByteId() => Uint8List.fromList([
    _byte(h1, 'h1'),
    _byte(h2, 'h2'),
    _byte(a1, 'a1'),
    _byte(a2, 'a2'),
  ]);

  Uint8List toTwoByteId() =>
      Uint8List.fromList([_byte(a1, 'a1'), _byte(a2, 'a2')]);

  static int _byte(int value, String name) {
    if (value < 0 || value > 0xff) {
      throw CuteConfigurationFailure('$name must be between 0 and 255.');
    }
    return value;
  }
}

class CuteSessionConfig {
  const CuteSessionConfig({
    this.trafficType = CuteTrafficType.typeA,
    this.subtype = CuteTrafficSubtype.conversational,
    this.characterSet = CuteCharacterSet.ascii7Bit,
    this.multiplexMode = CuteMultiplexMode.singleAscu,
    this.addressHeader = CuteAddressHeader.none,
    this.presentation = CutePresentation.p1024b,
    this.h1 = 0,
    this.h2 = 0,
    this.ascuAddresses = const [],
    this.flowId,
    this.senderHld,
    this.recipientHld,
  });

  final CuteTrafficType trafficType;
  final CuteTrafficSubtype subtype;
  final CuteCharacterSet characterSet;
  final CuteMultiplexMode multiplexMode;
  final CuteAddressHeader addressHeader;
  final CutePresentation presentation;
  final int h1;
  final int h2;
  final List<CuteAscuAddress> ascuAddresses;
  final int? flowId;
  final int? senderHld;
  final int? recipientHld;

  void validate() {
    _byte(h1, 'h1');
    _byte(h2, 'h2');
    if (flowId != null) _byte(flowId!, 'flowId');
    if (senderHld != null) _word(senderHld!, 'senderHld');
    if (recipientHld != null) _word(recipientHld!, 'recipientHld');

    if (trafficType == CuteTrafficType.typeA &&
        subtype == CuteTrafficSubtype.conversational &&
        !_validConversationalHeaderPair(multiplexMode, addressHeader)) {
      throw const CuteConfigurationFailure(
        'Conversational MATIP multiplex mode and address header are incoherent.',
      );
    }

    if (trafficType == CuteTrafficType.typeA &&
        subtype != CuteTrafficSubtype.conversational &&
        !_validHostHeaderPair(multiplexMode, addressHeader)) {
      throw const CuteConfigurationFailure(
        'Host-to-host MATIP multiplex mode and address header are incoherent.',
      );
    }

    if (trafficType == CuteTrafficType.typeB &&
        (senderHld == null) != (recipientHld == null)) {
      throw const CuteConfigurationFailure(
        'Type B MATIP must provide both senderHld and recipientHld, or neither.',
      );
    }

    for (final address in ascuAddresses) {
      address.toFourByteId();
    }
  }

  int get dataIdLength {
    if (trafficType == CuteTrafficType.typeB) return 0;
    if (subtype == CuteTrafficSubtype.conversational) {
      return switch ((addressHeader, presentation)) {
        (CuteAddressHeader.full, CutePresentation.p1024c) => 5,
        (CuteAddressHeader.full, _) => 4,
        (CuteAddressHeader.partial, CutePresentation.p1024c) => 3,
        (CuteAddressHeader.partial, _) => 2,
        (CuteAddressHeader.none, _) => 0,
      };
    }
    return switch (addressHeader) {
      CuteAddressHeader.full => 3,
      CuteAddressHeader.partial => 1,
      CuteAddressHeader.none => 0,
    };
  }

  static bool _validConversationalHeaderPair(
    CuteMultiplexMode multiplex,
    CuteAddressHeader header,
  ) {
    return switch (multiplex) {
      CuteMultiplexMode.groupWithFourByteAscu =>
        header == CuteAddressHeader.full,
      CuteMultiplexMode.groupWithTwoByteAscu =>
        header == CuteAddressHeader.full || header == CuteAddressHeader.partial,
      CuteMultiplexMode.singleAscu => true,
    };
  }

  static bool _validHostHeaderPair(
    CuteMultiplexMode multiplex,
    CuteAddressHeader header,
  ) {
    return switch (multiplex) {
      CuteMultiplexMode.groupWithFourByteAscu => false,
      CuteMultiplexMode.groupWithTwoByteAscu =>
        header == CuteAddressHeader.full || header == CuteAddressHeader.partial,
      CuteMultiplexMode.singleAscu => true,
    };
  }

  static int _byte(int value, String name) {
    if (value < 0 || value > 0xff) {
      throw CuteConfigurationFailure('$name must be between 0 and 255.');
    }
    return value;
  }

  static int _word(int value, String name) {
    if (value < 0 || value > 0xffff) {
      throw CuteConfigurationFailure('$name must be between 0 and 65535.');
    }
    return value;
  }
}

class CuteSessionStatus {
  const CuteSessionStatus({
    required this.state,
    required this.message,
    this.endpoint,
    this.lastChangedAt,
    this.lastError,
  });

  const CuteSessionStatus.idle()
    : state = CuteSessionState.idle,
      message = 'Idle',
      endpoint = null,
      lastChangedAt = null,
      lastError = null;

  final CuteSessionState state;
  final String message;
  final CuteEndpoint? endpoint;
  final DateTime? lastChangedAt;
  final Object? lastError;

  CuteSessionStatus copyWith({
    CuteSessionState? state,
    String? message,
    CuteEndpoint? endpoint,
    Object? lastError,
    bool clearError = false,
  }) {
    return CuteSessionStatus(
      state: state ?? this.state,
      message: message ?? this.message,
      endpoint: endpoint ?? this.endpoint,
      lastChangedAt: DateTime.now(),
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class CuteMessage {
  const CuteMessage({required this.payload, this.id = const []});

  final Uint8List payload;
  final List<int> id;

  String get text => String.fromCharCodes(payload);
}

class CuteConnectionOptions {
  const CuteConnectionOptions({
    this.connectTimeout = const Duration(seconds: 10),
    this.sessionOpenTimeout = const Duration(seconds: 10),
    this.closeTimeout = const Duration(seconds: 5),
  });

  final Duration connectTimeout;
  final Duration sessionOpenTimeout;
  final Duration closeTimeout;
}

class CuteConfigurationFailure implements Exception {
  const CuteConfigurationFailure(this.message);

  final String message;

  @override
  String toString() => 'CuteConfigurationFailure: $message';
}

class CuteProtocolFailure implements Exception {
  const CuteProtocolFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) return 'CuteProtocolFailure: $message';
    return 'CuteProtocolFailure: $message ($cause)';
  }
}
