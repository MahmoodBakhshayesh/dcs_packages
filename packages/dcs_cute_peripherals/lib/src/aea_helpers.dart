import 'dart:convert';
import 'dart:typed_data';

/// Shared AEA helpers used across ARINC / SITA / RESA.
class AeaHelpers {
  AeaHelpers._();

  static const int som = 0x80;
  static const int eom = 0xff;

  static List<int> asciiBytes(String text) => utf8.encode(text);

  /// SITA-style printer framing: `0x80` + body + `0xFF`.
  static Uint8List frameSita(List<int> body, {bool addAdPrefix = false}) {
    final payload = <int>[
      if (addAdPrefix) ...asciiBytes('AD;'),
      ...body,
    ];
    return Uint8List.fromList([som, ...payload, eom]);
  }

  /// ARINC Muse AEA wrap: `(0x60 | LCMD_AEA_DATA)` + `/` + body.
  static Uint8List wrapArincAea(List<int> body) {
    return Uint8List.fromList([0x61, 0x2f, ...body]);
  }

  static String decodeAscii(List<int> bytes) {
    return const Latin1Decoder(allowInvalid: true)
        .convert(bytes)
        .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '');
  }

  /// Parse paper-ready hint from `ST;...` reply (field index 6 when present).
  static bool? paperOkFromSt(String reply) {
    final text = reply.trim();
    if (!text.toUpperCase().startsWith('ST')) return null;
    final parts = text.split(';');
    if (parts.length <= 6) return null;
    final code = parts[6].trim();
    if (code.isEmpty) return null;
    return code == '0' || code.toUpperCase() == 'OK' || code == '1';
  }
}
