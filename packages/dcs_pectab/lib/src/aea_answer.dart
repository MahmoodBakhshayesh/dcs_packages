import 'model.dart';

/// Decoded AEA printer answer (SPEC §4).
final class AeaAnswer {
  const AeaAnswer({required this.raw, required this.code, this.itemNo, this.elementIndexHint, this.meaning});

  final String raw;
  final String code; // PROK, ERR3, ERR8, …
  final String? itemNo;
  final int? elementIndexHint;
  final String? meaning;
}

/// Maps printer answers back to canvas elements.
abstract final class AeaAnswerDecoder {
  static const meanings = <String, String>{
    'PROK': 'print ok',
    'ERR2': 'illogical command',
    'ERR3': 'incorrect data field',
    'ERR4': 'incorrect sequence',
    'ERR5': 'unsuccessful print',
    'ERR6': 'PECTAB missing',
    'ERR7': 'busy (revalidation / check-in in progress)',
    'ERR8': 'illogical PECTAB data',
    'ERR9': 'memory exceeded',
    'ERRO': 'object (logo) not found',
    'ERRS': 'document unknown',
    'ERRT': 'template load not ok',
    'ERRL': 'logo download error',
    'LTOK': 'logo load ok',
    'FTOK': 'font load ok',
    'PCOK': 'table cleared',
  };

  /// Parse a printer response fragment, e.g. `ERR303=12`, `ERR8`, `…PROK`.
  static AeaAnswer decode(String raw, {PectabDocument? document}) {
    final text = raw.trim().toUpperCase();
    // Strip leading noise (device prefixes).
    final match = RegExp(r'(PROK|ERR[0-9A-Z]|LTOK|FTOK|PCOK)').firstMatch(text);
    if (match == null) {
      return AeaAnswer(raw: raw, code: 'UNKNOWN', meaning: null);
    }
    final code = match.group(1)!;
    String? itemNo;
    // ERR3=NN or ERR303=12 forms
    final field = RegExp(r'ERR3[^=]*=([0-9A-F]{2})').firstMatch(text) ?? RegExp(r'ERR3=([0-9A-F]{2})').firstMatch(text);
    if (field != null) itemNo = field.group(1);

    // ERR8 + element index / item (hypotheses: ERR812 or ERR8=12)
    final err8 = RegExp(r'ERR8[=]?([0-9A-F]{2})').firstMatch(text);
    if (code.startsWith('ERR8') && err8 != null) {
      itemNo ??= err8.group(1);
    }

    int? index;
    if (document != null && itemNo != null) {
      index = document.elements.indexWhere((e) => e.itemNo.toUpperCase() == itemNo);
      if (index < 0) index = null;
    }

    final baseCode = code.startsWith('ERR') && code.length > 4 ? code.substring(0, 4) : code;
    return AeaAnswer(
      raw: raw,
      code: baseCode,
      itemNo: itemNo,
      elementIndexHint: index,
      meaning: meanings[baseCode] ?? meanings[code],
    );
  }
}
