import 'dart:typed_data';

import 'arinc_defines.dart';

/// PCP32 RQB packet (16-byte header + body), little-endian by default.
class ArincRqb {
  ArincRqb({
    required this.command,
    this.commandStatus = 0,
    this.physicalStatus = 0,
    List<int>? reserved,
    List<int>? parameters,
    List<int>? body,
  })  : reserved = Uint8List.fromList(reserved ?? const [0, 0, 0, 0]),
        parameters = Uint8List.fromList(parameters ?? const [0, 0, 0, 0]),
        body = Uint8List.fromList(body ?? const []);

  int command;
  int commandStatus;
  int physicalStatus;
  final Uint8List reserved;
  final Uint8List parameters;
  Uint8List body;

  int get dataLength => body.length;

  static ArincRqb send(List<int> body) => ArincRqb(
        command: body.length >= 64000 ? ArincPcpCommand.send2 : ArincPcpCommand.send,
        body: body,
      );

  static ArincRqb commandOnly(int command, {List<int>? parameters}) => ArincRqb(
        command: command,
        parameters: parameters,
      );

  factory ArincRqb.decode(List<int> bytes) {
    if (bytes.length < 16) {
      throw FormatException('RQB header too short: ${bytes.length}');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final command = data.getUint16(0, Endian.little);
    final commandStatus = data.getUint16(2, Endian.little);
    final physicalStatus = data.getUint16(4, Endian.little);
    final reserved = bytes.sublist(6, 10);
    final dataLen = data.getUint16(10, Endian.little);
    final parameters = bytes.sublist(12, 16);
    final body = bytes.length > 16
        ? bytes.sublist(16, 16 + (dataLen.clamp(0, bytes.length - 16)))
        : const <int>[];
    return ArincRqb(
      command: command,
      commandStatus: commandStatus,
      physicalStatus: physicalStatus,
      reserved: reserved,
      parameters: parameters,
      body: body,
    );
  }

  Uint8List encode() {
    final out = Uint8List(16 + body.length);
    final data = ByteData.sublistView(out);
    data.setUint16(0, command, Endian.little);
    data.setUint16(2, commandStatus, Endian.little);
    data.setUint16(4, physicalStatus, Endian.little);
    out.setRange(6, 10, reserved);
    data.setUint16(10, body.length, Endian.little);
    out.setRange(12, 16, parameters);
    if (body.isNotEmpty) {
      out.setRange(16, 16 + body.length, body);
    }
    return out;
  }
}
