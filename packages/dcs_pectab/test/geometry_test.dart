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
}
