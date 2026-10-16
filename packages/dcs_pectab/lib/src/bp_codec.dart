import 'model.dart';

/// Boarding-pass element codec (SPEC §1.3–§1.4).
///
/// Classifies a tokenized BP body segment into [BpText], [BpBarcode],
/// [BpReserved], or leaves [UnknownElement] when the bytes are not understood.
abstract final class BpCodec {
  /// Classify [source] (without trailing `#`). Never throws — unknowns stay verbatim.
  static PectabElement parseElement(String source) {
    if (source.length < 2 || !_isHex(source[0]) || !_isHex(source[1])) {
      return UnknownElement(itemNo: '', source: source);
    }
    final itemNo = '${source[0].toUpperCase()}${source[1].toUpperCase()}';
    final rest = source.substring(2);
    if (rest.isEmpty) {
      return UnknownElement(itemNo: itemNo, source: source);
    }

    if (rest[0].toUpperCase() == 'B') {
      return _parseBarcode(itemNo, source, rest.substring(1)) ?? UnknownElement(itemNo: itemNo, source: source);
    }

    if (rest.length < 2 || !_isDigit(rest[0]) || !_isDigit(rest[1])) {
      return UnknownElement(itemNo: itemNo, source: source);
    }
    final length = int.parse(rest.substring(0, 2));
    final rem = rest.substring(2);
    if (rem.isEmpty) {
      return BpReserved(itemNo: itemNo, source: source, length: length);
    }

    final positions = <BpPos>[];
    var i = 0;
    while (i + 3 <= rem.length) {
      final row = rem[i];
      if (!_isBpRow(row)) break;
      final colStr = rem.substring(i + 1, i + 3);
      if (!_isDigit(colStr[0]) || !_isDigit(colStr[1])) break;
      final col = int.parse(colStr);
      if (col < 1 || col > 70) break;
      positions.add(BpPos(row: row.toUpperCase(), col: col));
      i += 3;
    }
    if (positions.isEmpty) {
      return UnknownElement(itemNo: itemNo, source: source);
    }

    var style = BpStyle.medium;
    if (i < rem.length) {
      final s = rem[i].toUpperCase();
      if (s == 'L') {
        style = BpStyle.small;
        i++;
      } else if (s == 'R') {
        style = BpStyle.bold;
        i++;
      } else {
        return UnknownElement(itemNo: itemNo, source: source);
      }
    }
    if (i != rem.length) {
      return UnknownElement(itemNo: itemNo, source: source);
    }

    return BpText(itemNo: itemNo, source: source, length: length, positions: positions, style: style);
  }

  static BpBarcode? _parseBarcode(String itemNo, String source, String afterB) {
    var rem = afterB;
    var rotate180 = false;
    if (rem.isNotEmpty && rem[0].toUpperCase() == 'R') {
      rotate180 = true;
      rem = rem.substring(1);
    }
    // type(1) + row(1) + col(2) + hh(2) + ecc(1) + hri(1)
    if (rem.length != 8) return null;
    final typeCode = rem[0];
    final row = rem[1];
    if (!_isBpRow(row)) return null;
    final colStr = rem.substring(2, 4);
    if (!_isDigit(colStr[0]) || !_isDigit(colStr[1])) return null;
    final col = int.parse(colStr);
    if (col < 1 || col > 70) return null;
    final hhStr = rem.substring(4, 6);
    if (!_isDigit(hhStr[0]) || !_isDigit(hhStr[1])) return null;
    final heightMm = int.parse(hhStr);
    final eccCh = rem[6];
    final hriCh = rem[7];
    if (!_isDigit(eccCh) || !_isDigit(hriCh)) return null;

    return BpBarcode(
      itemNo: itemNo,
      source: source,
      type: BpBarcodeType.fromCode(typeCode),
      typeCode: typeCode,
      pos: BpPos(row: row.toUpperCase(), col: col),
      heightMm: heightMm,
      ecc: int.parse(eccCh),
      hri: int.parse(hriCh),
      rotate180: rotate180,
    );
  }

  static bool _isHex(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
  }

  static bool _isDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 48 && c <= 57;
  }

  static bool _isBpRow(String ch) {
    final u = ch.toUpperCase().codeUnitAt(0);
    return u >= 65 && u <= 82; // A–R
  }
}
