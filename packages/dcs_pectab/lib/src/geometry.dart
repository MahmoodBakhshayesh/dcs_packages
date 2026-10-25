import 'dart:math' as math;

import 'catalog.dart';
import 'model.dart';

/// Physical / canvas geometry (ARCHITECTURE §3).
abstract final class PectabGeometry {
  // BP coupon
  static const double bpWidthMm = 203;
  static const double bpHeightMm = 80;
  static const int bpRows = 18; // A–R
  static const int bpCols = 70;
  static const int bpStubFromCol = 52;
  static double get bpCellW => bpWidthMm / bpCols; // ≈ 2.9
  static double get bpCellH => bpHeightMm / bpRows; // ≈ 4.44

  // BT tag
  static const double btWidthMm = 50;
  static const double btMaxLengthMm = 515;
  static const double btMirrorAxisMm = 25; // centre of width (legacy)
  static const double btDefaultMirrorPointMm = 270;

  /// Axis-aligned rectangle in mm (origin top-left of the coupon / tag).
  static MmRect? boundsOf(PectabElement element, {double? btLengthMm}) {
    final shapes = shapesOf(element);
    if (shapes.isEmpty) return null;
    var union = shapes.first.aabb;
    for (final sh in shapes.skip(1)) {
      union = union.expandToInclude(sh.aabb);
    }
    return union;
  }

  /// Oriented boxes the element prints as (one per BP position), in paper mm. Drawing, hit-testing and handles
  /// all use these, so what you see is what you click.
  ///
  /// - BP text: cell top-left anchor, `length` cells × one row.
  /// - BP barcode: anchored at the **bottom of its row**, rising upward by `heightMm` (manual p.6 — AEA elements
  ///   anchor lower-left); width by type (PDF417 ≈ 2.2 × height, QR square, 1-D ≈ 2.5 × height).
  /// - BT text: anchor (along, across); box `chars × 0.62·height` long, `height` high, shifted for centre / right
  ///   alignment, then turned about the anchor by the orient rotation (clockwise, y down).
  /// - BT barcode: bars `WW` mm tall centred across on `across`, [btBarcodeLengthMm] long (SPEC Q2 placeholder).
  /// - BT line (S): `HH / 10` mm thick, `WW` mm long across the tag, centred on `across`.
  static List<PectabShape> shapesOf(PectabElement element, {int? chars}) {
    return switch (element) {
      BpText(:final length, :final positions) => [
        for (final p in positions)
          PectabShape(
            ax: (p.col - 1) * bpCellW,
            ay: _rowIndex(p.row) * bpCellH,
            local: MmRect(left: 0, top: 0, width: length * bpCellW, height: bpCellH),
          ),
      ],
      BpBarcode e => [_bpBarcodeShape(e)],
      BpReserved() => const [],
      BtElement e => [?_btShape(e, chars: chars)],
      BoxElement e => [
        PectabShape(ax: e.x10 / 10.0, ay: e.y10 / 10.0, local: MmRect(left: 0, top: 0, width: e.l10 / 10.0, height: e.h10 / 10.0)),
      ],
      LineElement e => [
        PectabShape(ax: e.x10 / 10.0, ay: e.y10 / 10.0, local: MmRect(left: 0, top: 0, width: e.l10 / 10.0, height: e.h10 / 10.0)),
      ],
      _ => const [],
    };
  }

  /// Placeholder printed length of a BT barcode along the tag (SPEC Q2 — confirm on a printer).
  static const double btBarcodeLengthMm = 55;

  /// Characters a BT text element prints: literal, else the alias target's / its own catalog max length.
  static int btCharsOf(BtElement e) {
    final lit = e.literal;
    if (lit != null && lit.isNotEmpty) return lit.length;
    final target = e.aliasOf ?? e.itemNo;
    return PectabCatalog.btByItem(target)?.maxLength ?? 4;
  }

  /// Mirror copy (`M`) of a BT element: point reflection through (mirrorPoint, tagWidth / 2) — same box turned
  /// 180°, the way the second half of a real tag prints upside down.
  static PectabShape? mirrorShapeOf(
    BtElement element, {
    double mirrorPointMm = btDefaultMirrorPointMm,
    double tagWidthMm = btWidthMm,
    int? chars,
  }) {
    if (!element.mirror) return null;
    final primary = _btShape(element, chars: chars);
    if (primary == null) return null;
    return PectabShape(
      ax: 2 * mirrorPointMm - primary.ax,
      ay: tagWidthMm - primary.ay,
      local: primary.local,
      rotationDeg: (primary.rotationDeg + 180) % 360,
    );
  }

  static PectabShape _bpBarcodeShape(BpBarcode e) {
    final sw = int.tryParse(e.shortWidth ?? '');
    if (sw != null) {
      // Web-designer short form: width code drives the size (its own preview: ≥ 45 × 18 mm).
      final w = math.max(45.0, sw * 2.5);
      final h = math.max(18.0, sw.toDouble());
      final bottom = (_rowIndex(e.pos.row) + 1) * bpCellH;
      return PectabShape(ax: (e.pos.col - 1) * bpCellW, ay: bottom, local: MmRect(left: 0, top: -h, width: w, height: h));
    }
    final h = math.max(e.heightMm, 1).toDouble();
    final w = switch (e.type) {
      BpBarcodeType.qr => h,
      BpBarcodeType.pdf417 => 2.2 * h,
      _ => 2.5 * h, // 1-D
    };
    final bottom = (_rowIndex(e.pos.row) + 1) * bpCellH;
    return PectabShape(
      ax: (e.pos.col - 1) * bpCellW,
      ay: bottom,
      local: MmRect(left: 0, top: -h, width: w, height: h),
      rotationDeg: e.rotationDeg,
      rotateAboutCentre: true,
    );
  }

  static PectabShape? _btShape(BtElement e, {int? chars}) {
    final h = math.max(e.heightMm, 1).toDouble();
    final double len;
    final double thick;
    final double top;
    switch (e.kind) {
      case BtKind.rfid:
        return null;
      case BtKind.barcode:
        len = btBarcodeLengthMm;
        thick = math.max(e.strokeMm, 1).toDouble();
        top = -thick / 2;
      case BtKind.line:
        // Thin bar across the tag: rotate the local frame so "length" runs across.
        final across = math.max(e.strokeMm, 1).toDouble();
        final t = math.max(h / 10, 0.3);
        return PectabShape(
          ax: e.alongMm.toDouble(),
          ay: e.acrossMm.toDouble(),
          local: MmRect(left: 0, top: -across / 2, width: t, height: across),
          rotationDeg: e.orient.rotationDeg,
        );
      case BtKind.logo:
        len = math.max(e.strokeMm, 1).toDouble();
        thick = h;
        top = 0;
      case BtKind.text:
        final n = math.max(chars ?? btCharsOf(e), 1);
        len = n * 0.62 * h;
        thick = h;
        top = 0;
    }
    // Alignment centres / right-aligns text along its reading direction. Barcodes are already centred across
    // (bars), so they always start at the anchor along the tag.
    final left = e.kind == BtKind.barcode
        ? 0.0
        : switch (e.orient.align) {
            BtAlign.left => 0.0,
            BtAlign.centre => -len / 2,
            BtAlign.right => -len,
          };
    return PectabShape(
      ax: e.alongMm.toDouble(),
      ay: e.acrossMm.toDouble(),
      local: MmRect(left: left, top: top, width: len, height: thick),
      rotationDeg: e.orient.rotationDeg,
    );
  }

  /// Mirror ghost for a BT element (AEA designer formula).
  ///
  /// With [mirrorPointMm] (along) and [tagWidthMm] (across):
  /// `mirroredAlong = 2 * mirrorPoint - along`, `mirroredAcross = tagWidth - across`.
  ///
  /// Defaults match web AEA Designer (`mirrorPoint` 270, width [btWidthMm]).
  static MmRect? mirrorGhost(
    BtElement element, {
    double? btLengthMm,
    double mirrorPointMm = btDefaultMirrorPointMm,
    double tagWidthMm = btWidthMm,
  }) => mirrorShapeOf(element, mirrorPointMm: mirrorPointMm, tagWidthMm: tagWidthMm)?.aabb;

  /// Orientation character for a mirrored copy (AEA map 1↔5 … A↔E … I↔M).
  static String mirrorOrientCode(String code) {
    const map = {
      '1': '5',
      '2': '6',
      '3': '7',
      '4': '8',
      '5': '1',
      '6': '2',
      '7': '3',
      '8': '4',
      'A': 'E',
      'B': 'F',
      'C': 'G',
      'D': 'H',
      'E': 'A',
      'F': 'B',
      'G': 'C',
      'H': 'D',
      'I': 'M',
      'J': 'N',
      'K': 'O',
      'L': 'P',
      'M': 'I',
      'N': 'J',
      'O': 'K',
      'P': 'L',
    };
    if (code.isEmpty) return code;
    final upper = code[0].toUpperCase();
    final mapped = map[upper];
    if (mapped == null) return code;
    return code[0] == upper ? mapped : mapped.toLowerCase();
  }







  static int _rowIndex(String row) {
    final u = row.toUpperCase().codeUnitAt(0);
    return (u - 65).clamp(0, bpRows - 1);
  }
}

/// An element's printed box in paper mm: [local] rect relative to the anchor ([ax], [ay]), turned by
/// [rotationDeg] clockwise (y down) about the anchor — or about the box centre when [rotateAboutCentre].
final class PectabShape {
  const PectabShape({
    required this.ax,
    required this.ay,
    required this.local,
    this.rotationDeg = 0,
    this.rotateAboutCentre = false,
  });

  final double ax, ay;
  final MmRect local;
  final int rotationDeg;
  final bool rotateAboutCentre;

  /// Pivot of the rotation in paper mm.
  (double, double) get pivot => rotateAboutCentre
      ? (ax + local.left + local.width / 2, ay + local.top + local.height / 2)
      : (ax, ay);

  /// Paper-mm point of a local point (relative to the anchor).
  (double, double) toPaper(double lx, double ly) {
    final px = ax + lx;
    final py = ay + ly;
    final d = rotationDeg % 360;
    if (d == 0) return (px, py);
    final (cx, cy) = pivot;
    final rad = d * math.pi / 180;
    final c = _snap(math.cos(rad));
    final s = _snap(math.sin(rad));
    final dx = px - cx;
    final dy = py - cy;
    return (cx + dx * c - dy * s, cy + dx * s + dy * c);
  }

  /// Corners TL, TR, BR, BL (local frame) in paper mm.
  List<(double, double)> get corners => [
    toPaper(local.left, local.top),
    toPaper(local.right, local.top),
    toPaper(local.right, local.bottom),
    toPaper(local.left, local.bottom),
  ];

  MmRect get aabb {
    final cs = corners;
    var l = cs.first.$1, r = l, t = cs.first.$2, b = t;
    for (final (x, y) in cs) {
      if (x < l) l = x;
      if (x > r) r = x;
      if (y < t) t = y;
      if (y > b) b = y;
    }
    return MmRect(left: l, top: t, width: r - l, height: b - t);
  }

  /// Whether a paper-mm point lies inside the oriented box.
  bool contains(double x, double y, {double pad = 0}) {
    final (cx, cy) = pivot;
    final d = rotationDeg % 360;
    var lx = x, ly = y;
    if (d != 0) {
      final rad = -d * math.pi / 180;
      final c = _snap(math.cos(rad));
      final s = _snap(math.sin(rad));
      final dx = x - cx;
      final dy = y - cy;
      lx = cx + dx * c - dy * s;
      ly = cy + dx * s + dy * c;
    }
    lx -= ax;
    ly -= ay;
    return lx >= local.left - pad && lx <= local.right + pad && ly >= local.top - pad && ly <= local.bottom + pad;
  }

  static double _snap(double v) => v.abs() < 1e-12 ? 0 : v;

  @override
  String toString() => 'PectabShape(($ax,$ay) $local @$rotationDeg°)';
}

final class MmRect {
  const MmRect({required this.left, required this.top, required this.width, required this.height});

  final double left, top, width, height;

  double get right => left + width;
  double get bottom => top + height;

  MmRect expandToInclude(MmRect other) {
    final l = math.min(left, other.left);
    final t = math.min(top, other.top);
    final r = math.max(right, other.right);
    final b = math.max(bottom, other.bottom);
    return MmRect(left: l, top: t, width: r - l, height: b - t);
  }

  @override
  bool operator ==(Object other) =>
      other is MmRect && other.left == left && other.top == top && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'MmRect($left,$top ${width}x$height)';
}
