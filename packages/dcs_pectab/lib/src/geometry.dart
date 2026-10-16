import 'dart:math' as math;

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
    return switch (element) {
      BpText(:final length, :final positions) => _bpTextBounds(length, positions),
      BpBarcode(:final pos, :final heightMm, :final rotate180) => _bpBarcodeBounds(pos, heightMm, rotate180),
      BpReserved() => null,
      BtElement e => _btBounds(e, btLengthMm ?? btMaxLengthMm),
      BoxElement e => MmRect(left: e.x10 / 10.0, top: e.y10 / 10.0, width: e.l10 / 10.0, height: e.h10 / 10.0),
      LineElement e => MmRect(left: e.x10 / 10.0, top: e.y10 / 10.0, width: e.l10 / 10.0, height: e.h10 / 10.0),
      _ => null,
    };
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
  }) {
    final primary = _btBounds(element, btLengthMm ?? btMaxLengthMm);
    if (primary == null || !element.mirror) return null;
    final cx = primary.left + primary.width / 2;
    final cy = primary.top + primary.height / 2;
    final mx = 2 * mirrorPointMm - cx;
    final my = tagWidthMm - cy;
    return MmRect(
      left: mx - primary.width / 2,
      top: my - primary.height / 2,
      width: primary.width,
      height: primary.height,
    );
  }

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

  static MmRect? _bpTextBounds(int length, List<BpPos> positions) {
    if (positions.isEmpty) return null;
    MmRect? union;
    for (final p in positions) {
      final r = MmRect(
        left: (p.col - 1) * bpCellW,
        top: _rowIndex(p.row) * bpCellH,
        width: length * bpCellW,
        height: bpCellH,
      );
      union = union == null ? r : union.expandToInclude(r);
    }
    return union;
  }

  static MmRect _bpBarcodeBounds(BpPos pos, int heightMm, bool rotate180) {
    // Width unknown without data — use a placeholder 40 mm (Q5/calibration).
    const widthMm = 40.0;
    final left = (pos.col - 1) * bpCellW;
    final top = _rowIndex(pos.row) * bpCellH;
    final rect = MmRect(left: left, top: top, width: widthMm, height: heightMm.toDouble());
    if (!rotate180) return rect;
    // 180° around the position origin — same AABB for placeholder.
    return rect;
  }

  static MmRect? _btBounds(BtElement e, double tagLengthMm) {
    final along = e.alongMm.toDouble();
    final across = e.acrossMm.toDouble();
    // Estimate extent from height + stroke; rotation swaps axes.
    final h = math.max(e.heightMm, 1).toDouble();
    final w = math.max(e.strokeMm, 1).toDouble() * 4; // rough glyph width factor
    final rot = e.orient.rotationDeg;
    final double width;
    final double height;
    if (rot == 90 || rot == 270) {
      width = h;
      height = w;
    } else {
      width = w;
      height = h;
    }
    if (along > tagLengthMm || across > btWidthMm) {
      // Still return a rect — lint will flag out-of-canvas.
    }
    return MmRect(left: along, top: across, width: width, height: height);
  }

  static int _rowIndex(String row) {
    final u = row.toUpperCase().codeUnitAt(0);
    return (u - 65).clamp(0, bpRows - 1);
  }
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
