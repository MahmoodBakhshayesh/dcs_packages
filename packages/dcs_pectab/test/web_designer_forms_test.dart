import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

void main() {
  test('noise and line breaks before the preamble are dropped', () {
    final bt = Pectab.parse('copied: BTT1039~H0642172=#02C0 1004\n250202#');
    expect(bt, isA<BtDocument>());
    expect(bt.elements.single.itemNo, '02');
    expect(bt.serialize(), 'BTT1039~H0642172=#02C0 1004250202#');
    final bp = Pectab.parse('xx PT##?S9N#@;#TICKT#CHKIN#BOARD#01011101#0330G15#');
    expect(bp, isA<BpDocument>());
    expect(bp.elements.map((e) => e.itemNo), contains('03'));
  });

  test('web-designer short barcode form round-trips and moves', () {
    final doc = Pectab.parse('PT##?S9N#@;#TICKT#CHKIN#BOARD#01011101#FABRE422232#FBBE422232#');
    final fa = doc.elements.whereType<BpBarcode>().firstWhere((e) => e.itemNo == 'FA');
    expect(fa.pos, const BpPos(row: 'E', col: 42));
    expect(fa.shortWidth, '22');
    expect(fa.shortOrient, 'R');
    expect(doc.serialize(), 'PT##?S9N#@;#TICKT#CHKIN#BOARD#01011101#FABRE422232#FBBE422232#');
    fa
      ..pos = const BpPos(row: 'F', col: 40)
      ..dirty = true;
    expect(doc.serialize(), contains('#FABRF402232#'));
    final shape = PectabGeometry.shapesOf(fa).single;
    expect(shape.aabb.width, closeTo(55, 0.01));
  });

  test('manual barcode form is unchanged', () {
    final doc = Pectab.parse('PT##?S9N#@;#TICKT#CHKIN#BOARD#01011101#FAB6Q252033#');
    final fa = doc.elements.single as BpBarcode;
    expect(fa.shortWidth, isNull);
    expect(fa.type, BpBarcodeType.pdf417);
  });
}
