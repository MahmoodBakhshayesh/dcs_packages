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

    // AEA 4.3: `B` or `X` introduces a barcode.
    final marker = rest[0].toUpperCase();
    if (marker == 'B' || marker == 'X') {
      final barcode =
          _parseBarcode(itemNo, source, rest.substring(1)) ?? _parseSpecBarcode(itemNo, source, rest.substring(1));
      if (barcode == null) return UnknownElement(itemNo: itemNo, source: source);
      return barcode..marker = marker;
    }

    if (rest.length < 2 || !_isDigit(rest[0]) || !_isDigit(rest[1])) {
      return UnknownElement(itemNo: itemNo, source: source);
    }
    final length = int.parse(rest.substring(0, 2));
    var rem = rest.substring(2);
    if (rem.isEmpty) {
      return BpReserved(itemNo: itemNo, source: source, length: length);
    }

    // Magstripe-only: exactly 4 digits.
    if (rem.length == 4 && _allDigits(rem)) {
      return BpText(
        itemNo: itemNo,
        source: source,
        length: length,
        positions: const [],
        style: BpStyle.medium,
        magStripe: rem,
      );
    }

    String? magStripe;
    // Magstripe + positions: 4 digits then row…
    if (rem.length >= 4 && _allDigits(rem.substring(0, 4)) && rem.length > 4 && _isBpRow(rem[4])) {
      magStripe = rem.substring(0, 4);
      rem = rem.substring(4);
    }

    final positions = <BpPos>[];
    var i = 0;
    while (i + 3 <= rem.length) {
      final row = rem[i];
      if (!_isBpRow(row)) break;
      final colStr = rem.substring(i + 1, i + 3);
      if (!_isDigit(colStr[0]) || !_isDigit(colStr[1])) break;
      final col = int.parse(colStr);
      if (col < 1 || col > 95) break; // web allows cols past 72 for model
      positions.add(BpPos(row: row.toUpperCase(), col: col));
      i += 3;
    }
    if (positions.isEmpty && magStripe == null) {
      return UnknownElement(itemNo: itemNo, source: source);
    }

    String? steeringCmd;
    var style = BpStyle.medium;
    if (i < rem.length) {
      final tail = rem.substring(i);
      // Trailing L/R style only.
      if (tail.length == 1 && (tail.toUpperCase() == 'L' || tail.toUpperCase() == 'R')) {
        style = tail.toUpperCase() == 'L' ? BpStyle.small : BpStyle.bold;
      } else if (tail.isNotEmpty) {
        // Steering (and optional trailing style letter).
        if (tail.length > 1 &&
            (tail[tail.length - 1].toUpperCase() == 'L' || tail[tail.length - 1].toUpperCase() == 'R')) {
          style = tail[tail.length - 1].toUpperCase() == 'L' ? BpStyle.small : BpStyle.bold;
          steeringCmd = tail.substring(0, tail.length - 1);
        } else {
          steeringCmd = tail;
        }
      }
    }

    return BpText(
      itemNo: itemNo,
      source: source,
      length: length,
      positions: positions,
      style: style,
      magStripe: magStripe,
      steeringCmd: steeringCmd,
    );
  }

  static BpBarcode? _parseBarcode(String itemNo, String source, String afterB) {
    final short = _parseShortBarcode(itemNo, source, afterB);
    if (short != null) return short;
    var rem = afterB;
    // L = 90°, R = 180° (AEA manual R; L extended so Rotate can step 90°).
    var rotationDeg = 0;
    if (rem.isNotEmpty) {
      final o = rem[0].toUpperCase();
      if (o == 'R') {
        rotationDeg = 180;
        rem = rem.substring(1);
      } else if (o == 'L') {
        rotationDeg = 90;
        rem = rem.substring(1);
      }
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
      rotationDeg: rotationDeg,
    );
  }

  /// `pectab-setup.md` §8 form: type (alphanumeric) + one or two cells + height(2) + ECC(1) + module(1), e.g.
  /// `FABRC012232` (type `R`, cell C01). Tried after the manual / web forms so their parses never change.
  static BpBarcode? _parseSpecBarcode(String itemNo, String source, String afterB) {
    final m = RegExp(r'^([0-9A-Za-z])((?:[A-Ra-r]\d{2}){1,2})(\d{2})(\d)(\d)$').firstMatch(afterB);
    if (m == null) return null;
    final cells = m.group(2)!;
    BpPos? cell(int at) {
      final col = int.parse(cells.substring(at + 1, at + 3));
      if (col < 1 || col > 72) return null;
      return BpPos(row: cells[at].toUpperCase(), col: col);
    }

    final pos = cell(0);
    final pos2 = cells.length == 6 ? cell(3) : null;
    if (pos == null || (cells.length == 6 && pos2 == null)) return null;
    final typeCode = m.group(1)!;
    return BpBarcode(
      itemNo: itemNo,
      source: source,
      type: BpBarcodeType.fromCode(typeCode),
      typeCode: typeCode,
      pos: pos,
      pos2: pos2,
      heightMm: int.parse(m.group(3)!),
      ecc: int.parse(m.group(4)!),
      hri: int.parse(m.group(5)!),
    );
  }

  /// BP literal word after the item no (`50PASSENGER`) — printed as a label. Null for any other element.
  static String? literalOf(PectabElement el) {
    if (el is! UnknownElement || el.source.length < 3) return null;
    final rest = el.source.substring(2);
    final first = rest[0].toUpperCase();
    if (first == 'B' || first == 'X') return null;
    return RegExp(r'^[A-Z][A-Z .:/&-]*$').hasMatch(rest) ? rest : null;
  }

  /// Web-designer form: `B` + optional `R`/`L` + row + col(2) + width(2) + height(2), PDF417.
  static BpBarcode? _parseShortBarcode(String itemNo, String source, String afterB) {
    final m = RegExp(r'^([LR]?)([A-Ra-r])(\d{2})(\d{2})(\d{2})$').firstMatch(afterB);
    if (m == null) return null;
    final col = int.parse(m.group(3)!);
    if (col < 1 || col > 72) return null;
    final orient = m.group(1)!.toUpperCase();
    final rotationDeg = switch (orient) {
      'R' => 90,
      'L' => 270,
      _ => 0,
    };
    return BpBarcode(
      itemNo: itemNo,
      source: source,
      type: BpBarcodeType.pdf417,
      typeCode: '6',
      pos: BpPos(row: m.group(2)!.toUpperCase(), col: col),
      heightMm: int.parse(m.group(5)!),
      ecc: 0,
      hri: 0,
      rotationDeg: rotationDeg,
      shortWidth: m.group(4),
      shortOrient: orient,
    );
  }

  static bool _allDigits(String s) => s.split('').every(_isDigit);

  static bool _isDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 48 && c <= 57;
  }

  static bool _isHex(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
  }

  static bool _isBpRow(String ch) {
    final u = ch.toUpperCase().codeUnitAt(0);
    return u >= 65 && u <= 82; // A–R
  }
}
