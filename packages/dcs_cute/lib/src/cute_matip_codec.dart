import 'dart:convert';
import 'dart:typed_data';

import 'cute_models.dart';

class CuteMatipPacket {
  const CuteMatipPacket({
    required this.command,
    required this.payload,
    required this.rawBytes,
    required this.isControl,
  });

  final CuteMatipCommand command;
  final Uint8List payload;
  final Uint8List rawBytes;
  final bool isControl;

  bool get isAcceptedOpenConfirm {
    return command == CuteMatipCommand.openConfirm &&
        payload.isNotEmpty &&
        payload.first == 0x00;
  }

  int? get refusalCause {
    if (command != CuteMatipCommand.openConfirm || isAcceptedOpenConfirm) {
      return null;
    }
    return payload.isEmpty ? null : payload.last;
  }

  int? get closeCause {
    if (command != CuteMatipCommand.sessionClose) return null;
    return payload.isEmpty ? null : payload.last;
  }
}

class CuteMatipCodec {
  const CuteMatipCodec();

  static const version = 0x01;
  static const headerLength = 4;
  static const minPacketLength = headerLength;

  Uint8List sessionOpen(CuteSessionConfig config) {
    config.validate();
    return _packet(CuteMatipCommand.sessionOpen, _sessionOpenPayload(config));
  }

  Uint8List openConfirmAccepted([CuteSessionConfig? config]) {
    if (config == null ||
        config.trafficType != CuteTrafficType.typeA ||
        config.subtype != CuteTrafficSubtype.conversational) {
      return _packet(CuteMatipCommand.openConfirm, Uint8List.fromList([0]));
    }

    final count = config.ascuAddresses.length;
    final bytes = <int>[
      0x00,
      if (config.multiplexMode == CuteMultiplexMode.groupWithFourByteAscu)
        count >> 8,
      count & 0xff,
    ];
    for (final ascu in config.ascuAddresses) {
      bytes.addAll(
        config.multiplexMode == CuteMultiplexMode.groupWithFourByteAscu
            ? ascu.toFourByteId()
            : ascu.toTwoByteId(),
      );
    }
    return _packet(CuteMatipCommand.openConfirm, Uint8List.fromList(bytes));
  }

  Uint8List openConfirmRefused(int cause) {
    return _packet(
      CuteMatipCommand.openConfirm,
      Uint8List.fromList([_byte(cause, 'cause')]),
    );
  }

  Uint8List sessionClose({int cause = 0}) {
    return _packet(
      CuteMatipCommand.sessionClose,
      Uint8List.fromList([_byte(cause, 'cause')]),
    );
  }

  Uint8List data(
    CuteSessionConfig config, {
    required List<int> payload,
    List<int> id = const [],
  }) {
    config.validate();
    if (id.length != config.dataIdLength) {
      throw CuteConfigurationFailure(
        'MATIP data id must be ${config.dataIdLength} byte(s) for this session.',
      );
    }
    return _packet(
      CuteMatipCommand.data,
      Uint8List.fromList([...id, ...payload]),
    );
  }

  Uint8List textData(
    CuteSessionConfig config, {
    required String text,
    List<int> id = const [],
    Encoding encoding = ascii,
  }) {
    return data(config, payload: encoding.encode(text), id: id);
  }

  CuteMatipPacket decodePacket(List<int> bytes) {
    if (bytes.length < headerLength) {
      throw const CuteProtocolFailure('MATIP packet is shorter than 4 bytes.');
    }
    if (bytes[0] != version) {
      throw CuteProtocolFailure('Unsupported MATIP version byte: ${bytes[0]}.');
    }

    final control = (bytes[1] & 0x80) != 0;
    final command = CuteMatipCommand.fromHeader(
      control: control,
      code: bytes[1] & 0x7f,
    );
    final length = _readWord(bytes[2], bytes[3]);
    if (length != bytes.length) {
      throw CuteProtocolFailure(
        'MATIP packet length mismatch. Header=$length actual=${bytes.length}.',
      );
    }

    return CuteMatipPacket(
      command: command,
      payload: Uint8List.fromList(bytes.skip(headerLength).toList()),
      rawBytes: Uint8List.fromList(bytes),
      isControl: control,
    );
  }

  CuteMessage decodeData(CuteSessionConfig config, CuteMatipPacket packet) {
    if (packet.command != CuteMatipCommand.data) {
      throw const CuteProtocolFailure('MATIP packet is not a data packet.');
    }
    final idLength = config.dataIdLength;
    if (packet.payload.length < idLength) {
      throw const CuteProtocolFailure('MATIP data packet is missing its id.');
    }
    return CuteMessage(
      id: Uint8List.fromList(packet.payload.take(idLength).toList()),
      payload: Uint8List.fromList(packet.payload.skip(idLength).toList()),
    );
  }

  Uint8List _packet(CuteMatipCommand command, Uint8List payload) {
    final length = headerLength + payload.length;
    if (length > 0xffff) {
      throw const CuteConfigurationFailure(
        'MATIP packet length cannot exceed 65535 bytes.',
      );
    }
    final commandByte = command == CuteMatipCommand.data
        ? 0x00
        : 0x80 | command.code;
    return Uint8List.fromList([
      version,
      commandByte,
      length >> 8,
      length & 0xff,
      ...payload,
    ]);
  }

  Uint8List _sessionOpenPayload(CuteSessionConfig config) {
    if (config.trafficType == CuteTrafficType.typeB) {
      return _typeBSessionOpenPayload(config);
    }
    if (config.subtype == CuteTrafficSubtype.conversational) {
      return _typeAConversationalSessionOpenPayload(config);
    }
    return _typeAHostSessionOpenPayload(config);
  }

  Uint8List _typeAConversationalSessionOpenPayload(CuteSessionConfig config) {
    final count = config.ascuAddresses.length;
    final bytes = <int>[
      0x10 | config.characterSet.code,
      (config.subtype.code & 0x0f) << 4,
      0x00,
      (config.multiplexMode.code << 6) |
          (config.addressHeader.code << 4) |
          config.presentation.code,
      _byte(config.h1, 'h1'),
      _byte(config.h2, 'h2'),
      0x00,
      0x00,
      0x00,
      0x00,
      count >> 8,
      count & 0xff,
    ];
    for (final ascu in config.ascuAddresses) {
      bytes.addAll(
        config.multiplexMode == CuteMultiplexMode.groupWithFourByteAscu
            ? ascu.toFourByteId()
            : ascu.toTwoByteId(),
      );
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List _typeAHostSessionOpenPayload(CuteSessionConfig config) {
    return Uint8List.fromList([
      0x10 | config.characterSet.code,
      (config.subtype.code & 0x0f) << 4,
      0x00,
      (config.multiplexMode.code << 6) | (config.addressHeader.code << 4),
      _byte(config.h1, 'h1'),
      _byte(config.h2, 'h2'),
      0x00,
      0x00,
      if (config.flowId != null) _byte(config.flowId!, 'flowId'),
    ]);
  }

  Uint8List _typeBSessionOpenPayload(CuteSessionConfig config) {
    final hasHld = config.senderHld != null && config.recipientHld != null;
    final bytes = <int>[
      config.characterSet.code,
      hasHld ? 0x22 : 0x00,
      if (hasHld) ...[
        config.senderHld! >> 8,
        config.senderHld! & 0xff,
        config.recipientHld! >> 8,
        config.recipientHld! & 0xff,
      ],
    ];
    return Uint8List.fromList(bytes);
  }
}

class CuteMatipDecoder {
  final _buffer = <int>[];
  final _packets = <CuteMatipPacket>[];
  final _codec = const CuteMatipCodec();

  int get bufferedBytes => _buffer.length;

  void add(List<int> chunk) {
    _buffer.addAll(chunk);
    _drain();
  }

  List<CuteMatipPacket> takePackets() {
    final packets = List<CuteMatipPacket>.of(_packets);
    _packets.clear();
    return packets;
  }

  void reset() {
    _buffer.clear();
    _packets.clear();
  }

  void _drain() {
    while (_buffer.length >= CuteMatipCodec.headerLength) {
      final versionIndex = _buffer.indexOf(CuteMatipCodec.version);
      if (versionIndex == -1) {
        _buffer.clear();
        return;
      }
      if (versionIndex > 0) {
        _buffer.removeRange(0, versionIndex);
      }
      if (_buffer.length < CuteMatipCodec.headerLength) return;

      final length = _readWord(_buffer[2], _buffer[3]);
      if (length < CuteMatipCodec.minPacketLength) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < length) return;

      final frame = _buffer.take(length).toList();
      _packets.add(_codec.decodePacket(frame));
      _buffer.removeRange(0, length);
    }
  }
}

int _readWord(int high, int low) => (high << 8) | low;

int _byte(int value, String name) {
  if (value < 0 || value > 0xff) {
    throw CuteConfigurationFailure('$name must be between 0 and 255.');
  }
  return value;
}
