import 'model.dart';

/// BOX / LINE template codec (SPEC §1.5). Units are 1/10 mm.
abstract final class TemplateCodec {
  /// Classify a template body segment. Accepts optional 2-hex item prefix
  /// (`01B…`, `03S…`) or bare AEA forms (`B0200…`, `S0200…`).
  static PectabElement parseElement(String source) {
    if (source.isEmpty) return UnknownElement(itemNo: '', source: source);

    var itemNo = '';
    var body = source;
    if (source.length >= 3 && _isHex(source[0]) && _isHex(source[1])) {
      final kind = source[2].toUpperCase();
      if (kind == 'B' || kind == 'S') {
        itemNo = '${source[0].toUpperCase()}${source[1].toUpperCase()}';
        body = source.substring(2);
      }
    }

    if (body.isEmpty) return UnknownElement(itemNo: itemNo, source: source);
    final kind = body[0].toUpperCase();
    final rem = body.substring(1);

    if (kind == 'B') {
      // xxxx(4) yyy(3) hhh(3) llll(4) bbb(3) rrrrr(5) = 22
      if (rem.length < 22 || !_allDigits(rem.substring(0, 22))) {
        return UnknownElement(itemNo: itemNo, source: source);
      }
      if (rem.length != 22) {
        return UnknownElement(itemNo: itemNo, source: source);
      }
      return BoxElement(
        itemNo: itemNo,
        source: source,
        x10: int.parse(rem.substring(0, 4)),
        y10: int.parse(rem.substring(4, 7)),
        h10: int.parse(rem.substring(7, 10)),
        l10: int.parse(rem.substring(10, 14)),
        border10: int.parse(rem.substring(14, 17)),
        reserved: rem.substring(17, 22),
      );
    }

    if (kind == 'S') {
      // xxxx(4) yyy(3) hhh(3) llll(4) rrrrr(5) = 19
      if (rem.length != 19 || !_allDigits(rem)) {
        return UnknownElement(itemNo: itemNo, source: source);
      }
      return LineElement(
        itemNo: itemNo,
        source: source,
        x10: int.parse(rem.substring(0, 4)),
        y10: int.parse(rem.substring(4, 7)),
        h10: int.parse(rem.substring(7, 10)),
        l10: int.parse(rem.substring(10, 14)),
        reserved: rem.substring(14, 19),
      );
    }

    return UnknownElement(itemNo: itemNo, source: source);
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
