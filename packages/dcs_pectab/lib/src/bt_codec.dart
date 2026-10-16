import 'model.dart';

/// Bag-tag element codec (SPEC §2.3–§2.4).
abstract final class BtCodec {
  /// Classify [source] (without trailing `#`). Unknown forms stay [UnknownElement].
  static PectabElement parseElement(String source) {
    if (source.length < 2 || !_isHex(source[0]) || !_isHex(source[1])) {
      return UnknownElement(itemNo: '', source: source);
    }
    final itemNo = '${source[0].toUpperCase()}${source[1].toUpperCase()}';
    final rest = source.substring(2);
    if (rest.length < 2) {
      return UnknownElement(itemNo: itemNo, source: source);
    }

    final kindCode = rest[0];
    final kind = _kindOf(kindCode);
    if (kind == null) {
      return UnknownElement(itemNo: itemNo, source: source);
    }
    final variant = rest[1];
    if (!_isDigit(variant)) {
      return UnknownElement(itemNo: itemNo, source: source);
    }

    var i = 2;
    var mirror = false;
    var spaceBeforeOrient = false;
    if (i < rest.length && rest[i] == ' ') {
      spaceBeforeOrient = true;
      i++;
    } else if (i < rest.length && rest[i].toUpperCase() == 'M') {
      mirror = true;
      i++;
    } else {
      // Neither space nor M — not a form we understand (keep verbatim).
      return UnknownElement(itemNo: itemNo, source: source);
    }

    if (i >= rest.length) {
      return UnknownElement(itemNo: itemNo, source: source);
    }
    final orientCode = rest[i];
    final orient = BtOrient.tryParse(orientCode);
    if (orient == null) {
      return UnknownElement(itemNo: itemNo, source: source);
    }
    // Preserve original case of the orient character.
    final orientCodeRaw = orientCode;
    i++;

    // XXX(3) YY(2) HH(2) WW(2)
    if (i + 9 > rest.length) {
      return UnknownElement(itemNo: itemNo, source: source);
    }
    final alongStr = rest.substring(i, i + 3);
    final acrossStr = rest.substring(i + 3, i + 5);
    final heightStr = rest.substring(i + 5, i + 7);
    final strokeStr = rest.substring(i + 7, i + 9);
    if (![alongStr, acrossStr, heightStr, strokeStr].every(_allDigits)) {
      return UnknownElement(itemNo: itemNo, source: source);
    }
    i += 9;

    String? literal;
    String? aliasOf;
    if (i < rest.length) {
      final tail = rest.substring(i);
      if (tail.startsWith('=')) {
        final ref = tail.substring(1);
        if (ref.length == 2 && _isHex(ref[0]) && _isHex(ref[1])) {
          aliasOf = ref.toUpperCase();
        } else {
          return UnknownElement(itemNo: itemNo, source: source);
        }
      } else {
        literal = tail;
      }
    }

    return BtElement(
      itemNo: itemNo,
      source: source,
      kind: kind,
      kindCode: kindCode, // preserve exact letter (B vs I, case)
      variant: variant,
      mirror: mirror,
      orient: BtOrient(
        code: orientCodeRaw,
        rotationDeg: orient.rotationDeg,
        whiteOnBlack: orient.whiteOnBlack,
        align: orient.align,
      ),
      orientCode: orientCodeRaw,
      alongMm: int.parse(alongStr),
      acrossMm: int.parse(acrossStr),
      heightMm: int.parse(heightStr),
      strokeMm: int.parse(strokeStr),
      literal: literal,
      aliasOf: aliasOf,
      spaceBeforeOrient: spaceBeforeOrient,
    );
  }

  static BtKind? _kindOf(String code) {
    return switch (code.toUpperCase()) {
      'C' || 'K' => BtKind.text,
      'B' || 'I' => BtKind.barcode,
      'S' => BtKind.line,
      'L' => BtKind.logo,
      'R' || 'T' => BtKind.rfid,
      _ => null,
    };
  }

  static bool _allDigits(String s) => s.split('').every(_isDigit);

  static bool _isHex(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
  }

  static bool _isDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 48 && c <= 57;
  }
}
