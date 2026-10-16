/// PECTAB document model (ARCHITECTURE §2). Codecs fill typed fields in P3–P5;
/// the tokenizer (P2) always keeps [PectabElement.source] verbatim for round-trip.
library;

/// Boarding-pass text style (trailing `L` / `R` / none).
enum BpStyle { small, medium, bold }

/// BP barcode symbology digit (SPEC §1.4 / Q5).
enum BpBarcodeType {
  /// Digit `1` — hypothesis: Interleaved 2 of 5.
  oneD1,

  /// Digit `2` — hypothesis: Code 128.
  oneD2,

  /// Digit `5` — QR.
  qr,

  /// Digit `6` — PDF417.
  pdf417,

  /// Any other type digit — kept for round-trip via [code].
  other;

  static BpBarcodeType fromCode(String code) {
    return switch (code) {
      '1' => BpBarcodeType.oneD1,
      '2' => BpBarcodeType.oneD2,
      '5' => BpBarcodeType.qr,
      '6' => BpBarcodeType.pdf417,
      _ => BpBarcodeType.other,
    };
  }

  String get code => switch (this) {
    BpBarcodeType.oneD1 => '1',
    BpBarcodeType.oneD2 => '2',
    BpBarcodeType.qr => '5',
    BpBarcodeType.pdf417 => '6',
    BpBarcodeType.other => '?',
  };
}

/// One BP print position: row A–R + column 01–70.
final class BpPos {
  const BpPos({required this.row, required this.col});

  final String row; // A–R
  final int col; // 1–70

  @override
  bool operator ==(Object other) => other is BpPos && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => '$row${col.toString().padLeft(2, '0')}';
}

/// BT element kind letter.
enum BtKind {
  text, // C or K
  barcode, // B or I
  line, // S
  logo, // L
  rfid, // R or T (RFID OID + data in [BtElement.literal])
}

/// BT tag stock family from the header id.
enum BtTagKind {
  standard, // 1039 / 1050
  limitedRelease, // 1139
  cabin, // 1239
  other,
}

/// Orientation / style / alignment (SPEC §2.4): `1`–`8`, `A`–`H`, `I`–`P`.
final class BtOrient {
  const BtOrient({required this.code, required this.rotationDeg, required this.whiteOnBlack, required this.align});

  final String code;
  final int rotationDeg; // 0, 90, 180, 270
  final bool whiteOnBlack;
  final BtAlign align;

  static BtOrient? tryParse(String code) {
    if (code.isEmpty) return null;
    final c = code[0].toUpperCase();
    const digits = '12345678';
    const centres = 'ABCDEFGH';
    const rights = 'IJKLMNOP';
    late final int index;
    late final BtAlign align;
    if (digits.contains(c)) {
      index = digits.indexOf(c);
      align = BtAlign.left;
    } else if (centres.contains(c)) {
      index = centres.indexOf(c);
      align = BtAlign.centre;
    } else if (rights.contains(c)) {
      index = rights.indexOf(c);
      align = BtAlign.right;
    } else {
      return null;
    }
    final rotationDeg = const [0, 0, 90, 90, 180, 180, 270, 270][index];
    final whiteOnBlack = index.isOdd;
    return BtOrient(
      code: code[0], // preserve caller's case via caller; table uses upper
      rotationDeg: rotationDeg,
      whiteOnBlack: whiteOnBlack,
      align: align,
    );
  }
}

enum BtAlign { left, centre, right }

/// Root document. [header] and each element's [PectabElement.source] are verbatim.
sealed class PectabDocument {
  PectabDocument({required this.header, required this.elements, this.trailing});

  /// Verbatim preamble including its trailing `#` when the stream uses `#`
  /// separators (e.g. `PT##?S9N#@;#TICKT#CHKIN#BOARD#01011101#` /
  /// `BTT1039~H0642172=#`).
  String header;

  /// Body elements in stream order.
  List<PectabElement> elements;

  /// Anything after the last `#`, verbatim. Null when the stream ends with `#`
  /// (the usual case).
  String? trailing;

  /// Full stream: header + each element source + `#` + optional trailing.
  /// Dirty elements are re-serialized; clean ones emit [PectabElement.source].
  String serialize() {
    final buf = StringBuffer(header);
    for (final e in elements) {
      buf.write(e.dirty ? e.serializeEdited() : e.source);
      buf.write('#');
    }
    final t = trailing;
    if (t != null && t.isNotEmpty) buf.write(t);
    return buf.toString();
  }
}

final class BpDocument extends PectabDocument {
  BpDocument({
    required super.header,
    required super.elements,
    super.trailing,
    required this.tableId,
    required this.emd,
  });

  /// Char after `?` in the PT header (`S`, `A`, `1`, …).
  String tableId;

  /// True when the header uses `E9` (EMD / invoice) instead of `S9`.
  bool emd;
}

final class BtDocument extends PectabDocument {
  BtDocument({
    required super.header,
    required super.elements,
    super.trailing,
    required this.version,
    required this.kind,
    this.continuationChar = '~',
    this.autoIncrement = 'H',
    this.colorChar = '0',
    this.tagWidth10 = 642,
    this.mirrorPointMm = 270,
    this.elemRefChar = '=',
  });

  /// Version / PECTAB id (`1039`, `1050`, `1139`, `1239`, …).
  String version;

  BtTagKind kind;

  /// Header fields after `BTT` + table id (AEA designer parity).
  String continuationChar;
  String autoIncrement;
  String colorChar;

  /// Tag width in 1/10 mm (e.g. `642` → 64.2 mm physical; canvas often 50–54 mm).
  int tagWidth10;

  /// Vertical mirror point in mm (along the tag). Default `270`.
  int mirrorPointMm;

  /// Element data-ref character (usually `=`).
  String elemRefChar;

  /// Physical tag width for mirror preview (mm).
  double get tagWidthMm => tagWidth10 / 10.0;
}

/// Separate template stream (`TT01#…`) — BOX / LINE (P5).
final class TemplateDocument extends PectabDocument {
  TemplateDocument({required super.header, required super.elements, super.trailing, required this.tableId});

  String tableId;
}

/// Unclassified stream — header may be empty; every segment is an element.
final class RawDocument extends PectabDocument {
  RawDocument({required super.header, required super.elements, super.trailing});
}

sealed class PectabElement {
  PectabElement({required this.itemNo, required this.source, this.dirty = false});

  /// Item number as in the stream (`02`, `FA`, `D5`) — may be empty for
  /// non-item segments kept as [UnknownElement].
  String itemNo;

  /// Exact original text without the trailing `#`. Re-emitted when not [dirty].
  String source;

  /// Set by any edit; only dirty elements are re-serialized.
  bool dirty;

  /// Codec-specific rewrite when [dirty] is true.
  String serializeEdited() => source;

  void markDirty() => dirty = true;
}

final class BpText extends PectabElement {
  BpText({
    required super.itemNo,
    required super.source,
    super.dirty,
    required this.length,
    required this.positions,
    required this.style,
    this.magStripe,
    this.steeringCmd,
  });

  int length;
  List<BpPos> positions;
  BpStyle style;

  /// Optional 4-digit magstripe block before print positions (AEA Variable).
  String? magStripe;

  /// Optional steering letters after the last position (e.g. `K35J62` remainder).
  String? steeringCmd;

  /// True when [source] / mock looks like a logo print command (`@nn`).
  bool get isLogoCommand {
    final s = steeringCmd ?? '';
    return s.startsWith('@') || (positions.isEmpty && (magStripe?.startsWith('@') ?? false));
  }

  @override
  String serializeEdited() {
    final styleSuffix = switch (style) {
      BpStyle.small => 'L',
      BpStyle.bold => 'R',
      BpStyle.medium => '',
    };
    final len = length.clamp(0, 99).toString().padLeft(2, '0');
    final mag = magStripe ?? '';
    final steer = steeringCmd ?? '';
    return '$itemNo$len$mag${positions.map((p) => p.toString()).join()}$steer$styleSuffix';
  }
}

final class BpBarcode extends PectabElement {
  BpBarcode({
    required super.itemNo,
    required super.source,
    super.dirty,
    required this.type,
    required this.typeCode,
    required this.pos,
    required this.heightMm,
    required this.ecc,
    required this.hri,
    required this.rotate180,
  });

  BpBarcodeType type;

  /// Original type digit (preserves unknown codes).
  String typeCode;
  BpPos pos;
  int heightMm;
  int ecc;
  int hri;
  bool rotate180;

  @override
  String serializeEdited() {
    final hh = heightMm.toString().padLeft(2, '0');
    return '$itemNo'
        'B'
        '${rotate180 ? 'R' : ''}'
        '$typeCode'
        '$pos'
        '$hh'
        '$ecc'
        '$hri';
  }
}

final class BpReserved extends PectabElement {
  BpReserved({required super.itemNo, required super.source, super.dirty, required this.length});

  int length;

  @override
  String serializeEdited() {
    final len = length.clamp(0, 99).toString().padLeft(2, '0');
    return '$itemNo$len';
  }
}

final class BtElement extends PectabElement {
  BtElement({
    required super.itemNo,
    required super.source,
    super.dirty,
    required this.kind,
    required this.kindCode,
    required this.variant,
    required this.mirror,
    required this.orient,
    required this.orientCode,
    required this.alongMm,
    required this.acrossMm,
    required this.heightMm,
    required this.strokeMm,
    this.literal,
    this.aliasOf,
    this.spaceBeforeOrient = true,
  });

  BtKind kind;

  /// Original kind letter (`C`/`K`/`B`/`I`/`S`/`L`/`R`/`T`) — preserve case / B vs I.
  String kindCode;

  /// Digit after the kind (`0`/`1`) — keep verbatim (Q1).
  String variant;
  bool mirror;
  BtOrient orient;

  /// Original orientation character — preserve `E` vs `5`, `A` vs `1`.
  String orientCode;
  int alongMm;
  int acrossMm;
  int heightMm;
  int strokeMm;
  String? literal;
  String? aliasOf;

  /// True when a space stood for "no mirror" in the source (`C0 1…` vs `C0M1…`).
  bool spaceBeforeOrient;

  @override
  String serializeEdited() {
    final mirrorOrSpace = mirror ? 'M' : (spaceBeforeOrient ? ' ' : ' ');
    final geo =
        '${alongMm.toString().padLeft(3, '0')}'
        '${acrossMm.toString().padLeft(2, '0')}'
        '${heightMm.toString().padLeft(2, '0')}'
        '${strokeMm.toString().padLeft(2, '0')}';
    final tail = aliasOf != null ? '=${aliasOf!}' : (literal ?? '');
    return '$itemNo$kindCode$variant$mirrorOrSpace$orientCode$geo$tail';
  }
}

final class BoxElement extends PectabElement {
  BoxElement({
    required super.itemNo,
    required super.source,
    super.dirty,
    required this.x10,
    required this.y10,
    required this.h10,
    required this.l10,
    required this.border10,
    required this.reserved,
  });

  int x10, y10, h10, l10, border10;
  String reserved;

  @override
  String serializeEdited() {
    final body =
        'B'
        '${x10.toString().padLeft(4, '0')}'
        '${y10.toString().padLeft(3, '0')}'
        '${h10.toString().padLeft(3, '0')}'
        '${l10.toString().padLeft(4, '0')}'
        '${border10.toString().padLeft(3, '0')}'
        '$reserved';
    return itemNo.isEmpty ? body : '$itemNo$body';
  }
}

final class LineElement extends PectabElement {
  LineElement({
    required super.itemNo,
    required super.source,
    super.dirty,
    required this.x10,
    required this.y10,
    required this.h10,
    required this.l10,
    required this.reserved,
  });

  int x10, y10, h10, l10;
  String reserved;

  @override
  String serializeEdited() {
    final body =
        'S'
        '${x10.toString().padLeft(4, '0')}'
        '${y10.toString().padLeft(3, '0')}'
        '${h10.toString().padLeft(3, '0')}'
        '${l10.toString().padLeft(4, '0')}'
        '$reserved';
    return itemNo.isEmpty ? body : '$itemNo$body';
  }
}

/// Anything not (yet) understood — always verbatim.
final class UnknownElement extends PectabElement {
  UnknownElement({required super.itemNo, required super.source, super.dirty});
}
