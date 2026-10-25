import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

BpBarcode _bc(String token) => BpCodec.parseElement(token) as BpBarcode;

void main() {
  test('X marker parses and survives a rewrite', () {
    final b = _bc('FAX6Q252033');
    expect((b.marker, b.typeCode, b.pos.toString(), b.heightMm), ('X', '6', 'Q25', 20));
    b.heightMm = 21;
    expect(b.serializeEdited(), 'FAX6Q252133');
  });

  test('spec form: alphanumeric type, one or two cells', () {
    // `FABRC012232` also fits the web short form, which keeps precedence (existing tables parse as before);
    // the spec form covers what neither older form accepts, e.g. an alphanumeric type with two cells.
    final one = _bc('FABRC01D022232');
    expect(
      (one.typeCode, one.pos.toString(), one.pos2.toString(), one.heightMm, one.ecc, one.hri),
      ('R', 'C01', 'D02', 22, 3, 2),
    );
    expect(one.serializeEdited(), 'FABRC01D022232');
    final two = _bc('50B6R01C401651');
    expect((two.pos.toString(), two.pos2.toString(), two.heightMm), ('R01', 'C40', 16));
    expect(two.serializeEdited(), '50B6R01C401651');
  });

  test('manual long form is unchanged (R still = 180°)', () {
    final b = _bc('FAB6Q252033');
    expect((b.marker, b.rotationDeg, b.pos2), ('B', 0, null));
  });

  test('literalOf: BP words only', () {
    expect(BpCodec.literalOf(BpCodec.parseElement('50PASSENGER')), 'PASSENGER');
    expect(BpCodec.literalOf(BpCodec.parseElement('2305O07')), isNull);
    expect(BpCodec.literalOf(BpCodec.parseElement('50BOGUS')), isNull);
  });
}
