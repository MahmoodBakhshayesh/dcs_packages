import 'model.dart';

/// Tokenizes a PECTAB / template stream into a [PectabDocument].
///
/// Rules (ARCHITECTURE §2 / SPEC):
/// - [PectabDocument.header] and each [PectabElement.source] are verbatim slices
///   of the input (no trim, no case fold).
/// - Body segments after the header become [UnknownElement] until codecs (P3–P5)
///   classify them; [UnknownElement.itemNo] is filled when the segment starts
///   with two hex digits.
/// - [PectabDocument.serialize] of a freshly tokenized document equals [input]
///   byte-for-byte.
abstract final class PectabTokenizer {
  /// Parse [input] into a typed document shell (BP / BT / template / raw).
  static PectabDocument tokenize(String input) {
    if (input.isEmpty) {
      return RawDocument(header: '', elements: const []);
    }

    final upper = input.toUpperCase();
    if (upper.startsWith('PT')) {
      return _tokenizeBp(input);
    }
    if (upper.startsWith('BT')) {
      return _tokenizeBt(input);
    }
    if (upper.startsWith('TT')) {
      return _tokenizeTemplate(input);
    }
    return _tokenizeRaw(input);
  }

  static BpDocument _tokenizeBp(String input) {
    final end = _bpHeaderEnd(input);
    final header = input.substring(0, end);
    final (elements, trailing) = _bodyElements(input.substring(end));
    return BpDocument(
      header: header,
      elements: elements,
      trailing: trailing,
      tableId: _bpTableId(header),
      emd: _bpIsEmd(header),
    );
  }

  static BtDocument _tokenizeBt(String input) {
    final end = _btHeaderEnd(input);
    final header = input.substring(0, end);
    final (elements, trailing) = _bodyElements(input.substring(end));
    final version = _btVersion(header);
    return BtDocument(
      header: header,
      elements: elements,
      trailing: trailing,
      version: version,
      kind: _btTagKind(version),
    );
  }

  static TemplateDocument _tokenizeTemplate(String input) {
    final end = _firstHashEnd(input);
    final header = input.substring(0, end);
    final (elements, trailing) = _bodyElements(input.substring(end));
    final idMatch = RegExp(r'^TT([0-9A-Za-z]*)', caseSensitive: false).firstMatch(header);
    return TemplateDocument(header: header, elements: elements, trailing: trailing, tableId: idMatch?.group(1) ?? '');
  }

  static RawDocument _tokenizeRaw(String input) {
    final (elements, trailing) = _bodyElements(input);
    return RawDocument(header: '', elements: elements, trailing: trailing);
  }

  /// End index (exclusive) of the BP header, including its last `#`.
  ///
  /// Header tokens (SPEC §1.2 / ARCHITECTURE): `PT…`, `@;`, `TICKT`, `CHKIN`,
  /// `BOARD`, `01011101` — each followed by `#`. Stops at the first segment
  /// that is not one of those.
  static int _bpHeaderEnd(String input) {
    var i = 0;
    var sawPt = false;
    while (i < input.length) {
      final hash = input.indexOf('#', i);
      if (hash < 0) {
        return sawPt ? input.length : 0;
      }
      final seg = input.substring(i, hash);
      if (!_isBpHeaderSegment(seg, sawPt: sawPt)) {
        return i;
      }
      sawPt = true;
      i = hash + 1;
    }
    return i;
  }

  static bool _isBpHeaderSegment(String seg, {required bool sawPt}) {
    if (!sawPt) {
      return seg.length >= 2 && seg.substring(0, 2).toUpperCase() == 'PT';
    }
    // `PT##?S9N` yields an empty segment between the doubled `#`.
    if (seg.isEmpty) return true;
    // `?S9N` / `?A9N` / `?E9N` — table id + ATB flags after `PT##`.
    if (seg.startsWith('?')) return true;
    if (seg == '@;' || seg.startsWith('@')) return true;
    final u = seg.toUpperCase();
    if (u == 'TICKT' || u == 'CHKIN' || u == 'BOARD') return true;
    // Fixed ATB flags from the manual (Q3) — part of the header, not item 01.
    if (seg == '01011101') return true;
    return false;
  }

  /// BT header through the first `#` (e.g. `BTT1039~H0642172=#`).
  static int _btHeaderEnd(String input) {
    final hash = input.indexOf('#');
    if (hash < 0) return input.length;
    return hash + 1;
  }

  static int _firstHashEnd(String input) {
    final hash = input.indexOf('#');
    if (hash < 0) return input.length;
    return hash + 1;
  }

  /// Split [body] on `#` into element sources + optional trailing.
  static (List<PectabElement>, String?) _bodyElements(String body) {
    if (body.isEmpty) return (const [], null);

    final parts = body.split('#');
    if (body.endsWith('#')) {
      final sources = parts.sublist(0, parts.length - 1);
      return (sources.map(_elementFromSource).toList(growable: false), null);
    }

    if (parts.length == 1) {
      return (const [], parts[0]);
    }

    final sources = parts.sublist(0, parts.length - 1);
    return (sources.map(_elementFromSource).toList(growable: false), parts.last);
  }

  static PectabElement _elementFromSource(String source) {
    return UnknownElement(itemNo: _itemNoOf(source), source: source);
  }

  /// Leading 2 hex digits when present; otherwise empty.
  static String _itemNoOf(String source) {
    if (source.length < 2) return '';
    final a = source[0];
    final b = source[1];
    if (_isHex(a) && _isHex(b)) {
      return '${a.toUpperCase()}${b.toUpperCase()}';
    }
    return '';
  }

  static bool _isHex(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
  }

  static String _bpTableId(String header) {
    final m = RegExp(r'\?([0-9A-Za-z])').firstMatch(header);
    return m?.group(1) ?? '';
  }

  /// SPEC §1.2: EMD / invoice PECTAB changes `S9` → `E9` in the header
  /// (`PT##?S9N` → `PT##?E9N`).
  static bool _bpIsEmd(String header) {
    return RegExp(r'\?E9', caseSensitive: false).hasMatch(header);
  }

  static String _btVersion(String header) {
    final m = RegExp(r'^BT[T]?([0-9A-Za-z]+)', caseSensitive: false).firstMatch(header);
    return m?.group(1) ?? '';
  }

  static BtTagKind _btTagKind(String version) {
    return switch (version) {
      '1039' || '1050' => BtTagKind.standard,
      '1139' => BtTagKind.limitedRelease,
      '1239' => BtTagKind.cabin,
      _ => BtTagKind.other,
    };
  }
}
