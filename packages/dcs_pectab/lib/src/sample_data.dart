/// Sample print-data parser (SPEC §3): `CP#…` / `BTP…` → itemNo → value.
library;

final class PectabSampleData {
  const PectabSampleData({required this.kind, required this.header, required this.values});

  /// `CP` or `BTP`.
  final String kind;
  final String header;
  final Map<String, String> values;

  String? operator [](String itemNo) => values[itemNo.toUpperCase()];
}

abstract final class PectabSampleParser {
  /// Parse a CP / BTP (or bare `#`-separated item list) into item values.
  ///
  /// Barcode items (`FA`/`FB`): leading `B` in the value is stripped when present
  /// (same convention as the interim DCS parser).
  static PectabSampleData parse(String sample) {
    final raw = sample.trim();
    if (raw.isEmpty) {
      return const PectabSampleData(kind: '', header: '', values: {});
    }

    final upper = raw.toUpperCase();
    String kind = '';
    String header = '';
    var body = raw;

    if (upper.startsWith('BTP')) {
      kind = 'BTP';
      final hash = raw.indexOf('#');
      if (hash >= 0) {
        header = raw.substring(0, hash + 1);
        body = raw.substring(hash + 1);
      } else {
        header = raw;
        body = '';
      }
    } else if (upper.startsWith('CP')) {
      kind = 'CP';
      // `CP#1C01#…` — header through table id segment
      final parts = raw.split('#');
      if (parts.length >= 2) {
        header = '${parts[0]}#${parts[1]}#';
        body = parts.skip(2).join('#');
        if (raw.endsWith('#') && !body.endsWith('#') && body.isNotEmpty) {
          // keep join behaviour; values loop handles trailing
        }
      }
    }

    final values = <String, String>{};
    for (final segment in body.split('#')) {
      if (segment.isEmpty) continue;
      if (segment.length < 2 || !_isHex(segment[0]) || !_isHex(segment[1])) continue;
      final itemNo = '${segment[0].toUpperCase()}${segment[1].toUpperCase()}';
      var value = segment.substring(2);
      // BP barcode data often prefixed with B
      if (value.isNotEmpty && value[0].toUpperCase() == 'B' && (itemNo == 'FA' || itemNo == 'FB')) {
        value = value.substring(1);
      }
      values[itemNo] = value;
    }

    return PectabSampleData(kind: kind, header: header, values: values);
  }

  static bool _isHex(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
  }
}
