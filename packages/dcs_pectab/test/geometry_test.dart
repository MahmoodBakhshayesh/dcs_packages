import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

void main() {
  test('BP cell size golden numbers', () {
    expect(PectabGeometry.bpCellW, closeTo(203 / 70, 1e-9));
    expect(PectabGeometry.bpCellH, closeTo(80 / 18, 1e-9));
    expect(PectabGeometry.bpCellW, closeTo(2.9, 0.01));
    expect(PectabGeometry.bpCellH, closeTo(4.44, 0.01));
  });

  test('BP text at A01 length 5', () {
    final e = BpCodec.parseElement('0305A01') as BpText;
    final r = PectabGeometry.boundsOf(e)!;
    expect(r.left, 0);
    expect(r.top, 0);
    expect(r.width, closeTo(5 * PectabGeometry.bpCellW, 1e-9));
    expect(r.height, closeTo(PectabGeometry.bpCellH, 1e-9));
  });

  test('BP multi-position union', () {
    final e = BpCodec.parseElement('0705I26K54L') as BpText;
    final r = PectabGeometry.boundsOf(e)!;
    expect(r.left, closeTo(25 * PectabGeometry.bpCellW, 1e-9)); // col 26 → index 25
    expect(r.right, greaterThan(r.left));
  });

  test('BT mirror ghost uses mirrorPoint along + flip across', () {
    final e = BtCodec.parseElement('92C0M1020060202') as BtElement;
    expect(e.mirror, isTrue);
    final primary = PectabGeometry.boundsOf(e)!;
    expect(primary.left, 20);
    expect(primary.top, 6);
    final ghost = PectabGeometry.mirrorGhost(e, mirrorPointMm: 270, tagWidthMm: 50)!;
    final pcAlong = primary.left + primary.width / 2;
    final gcAlong = ghost.left + ghost.width / 2;
    expect(gcAlong + pcAlong, closeTo(2 * 270, 1e-6));
    final pcAcross = primary.top + primary.height / 2;
    final gcAcross = ghost.top + ghost.height / 2;
    expect(gcAcross + pcAcross, closeTo(50, 1e-6));
  });

  test('mirrorOrientCode pairs', () {
    expect(PectabGeometry.mirrorOrientCode('1'), '5');
    expect(PectabGeometry.mirrorOrientCode('A'), 'E');
    expect(PectabGeometry.mirrorOrientCode('I'), 'M');
    expect(PectabGeometry.mirrorOrientCode('5'), '1');
  });

  test('BOX / LINE mm from 1/10 mm fields', () {
    final box = TemplateCodec.parseElement('B0200240100050000500000') as BoxElement;
    final r = PectabGeometry.boundsOf(box)!;
    expect(r.left, 20);
    expect(r.top, 24);
    expect(r.width, 50);
    expect(r.height, 10);
  });

  group('oriented shapes (0.1.2)', () {
    test('manual BP barcode FAB6Q252033 rises from row Q and stays on the coupon', () {
      final e = BpCodec.parseElement('FAB6Q252033') as BpBarcode;
      final r = PectabGeometry.boundsOf(e)!;
      expect(r.bottom, closeTo(17 * PectabGeometry.bpCellH, 1e-9)); // bottom of row Q (index 16)
      expect(r.height, 20);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(PectabGeometry.bpHeightMm));
      expect(r.width, closeTo(44, 1e-9)); // PDF417 ≈ 2.2 × height
    });

    test('BT text length follows its characters (85 passenger name, 15 chars)', () {
      final e = BtCodec.parseElement('85C1 5230430201') as BtElement;
      final sh = PectabGeometry.shapesOf(e).single;
      expect(sh.local.width, closeTo(15 * 0.62 * 2, 1e-9));
      expect(sh.rotationDeg, 180); // orient 5
      // 180° about the anchor: the box lies before / above the anchor.
      final r = sh.aabb;
      expect(r.right, closeTo(230, 1e-9));
      expect(r.bottom, closeTo(43, 1e-9));
    });

    test('literal text uses its own length; centre alignment centres on the anchor', () {
      final e = BtCodec.parseElement('55C0 A299520201VIA:') as BtElement;
      final sh = PectabGeometry.shapesOf(e).single;
      expect(sh.local.width, closeTo(4 * 0.62 * 2, 1e-9));
      expect(sh.local.left, closeTo(-sh.local.width / 2, 1e-9));
    });

    test('manual BT licence-plate barcode fits the 50 mm tag across', () {
      final e = BtCodec.parseElement('03B1 A007260441') as BtElement;
      final r = PectabGeometry.boundsOf(e)!;
      expect(r.top, closeTo(26 - 20.5, 1e-9));
      expect(r.bottom, closeTo(26 + 20.5, 1e-9));
      expect(r.bottom, lessThanOrEqualTo(PectabGeometry.btWidthMm));
    });

    test('BT line S spans across the tag', () {
      final e = BtCodec.parseElement('56S0 A295270452') as BtElement;
      final r = PectabGeometry.boundsOf(e)!;
      expect(r.left, 295);
      expect(r.height, 52);
    });

    test('mirror shape is the element turned 180° through (mirrorPoint, width / 2)', () {
      final e = BtCodec.parseElement('92C0M1020060202') as BtElement;
      final p = PectabGeometry.shapesOf(e).single;
      final m = PectabGeometry.mirrorShapeOf(e, mirrorPointMm: 270, tagWidthMm: 50)!;
      expect(m.rotationDeg, (p.rotationDeg + 180) % 360);
      for (var i = 0; i < 4; i++) {
        final a = p.corners[i];
        final b = m.corners[i];
        expect(a.$1 + b.$1, closeTo(540, 1e-6));
        expect(a.$2 + b.$2, closeTo(50, 1e-6));
      }
    });

    test('contains() works in the rotated frame', () {
      final e = BtCodec.parseElement('85C1 5230430201') as BtElement;
      final sh = PectabGeometry.shapesOf(e).single;
      expect(sh.contains(225, 42), isTrue); // inside the 180° box (before / above the anchor)
      expect(sh.contains(235, 44), isFalse); // the unrotated side
    });
  });
}
