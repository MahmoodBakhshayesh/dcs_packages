import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

import 'fixtures/manual_samples.dart';

void main() {
  group('BtCodec basics', () {
    test('text with space orient', () {
      final e = BtCodec.parseElement('02C0 1004250202') as BtElement;
      expect(e.itemNo, '02');
      expect(e.kind, BtKind.text);
      expect(e.kindCode, 'C');
      expect(e.variant, '0');
      expect(e.mirror, isFalse);
      expect(e.spaceBeforeOrient, isTrue);
      expect(e.orientCode, '1');
      expect(e.orient.rotationDeg, 0);
      expect(e.alongMm, 4);
      expect(e.acrossMm, 25);
      expect(e.heightMm, 2);
      expect(e.strokeMm, 2);
      expect(e.literal, isNull);
      expect(e.aliasOf, isNull);
    });

    test('mirror M (no space)', () {
      final e = BtCodec.parseElement('51C0M2211070302') as BtElement;
      expect(e.mirror, isTrue);
      expect(e.spaceBeforeOrient, isFalse);
      expect(e.orientCode, '2');
      expect(e.alongMm, 211);
      expect(e.acrossMm, 7);
    });

    test('literal and alias', () {
      final lit = BtCodec.parseElement('80C0 5233480202P/W') as BtElement;
      expect(lit.literal, 'P/W');
      final alias = BtCodec.parseElement('D5C0 5430410303=89') as BtElement;
      expect(alias.itemNo, 'D5');
      expect(alias.aliasOf, '89');
      expect(alias.literal, isNull);
    });

    test('barcode B and I, line S, RFID R, text K', () {
      expect((BtCodec.parseElement('03B1 A007260441') as BtElement).kind, BtKind.barcode);
      expect((BtCodec.parseElement('03I1 A007260441') as BtElement).kindCode, 'I');
      expect((BtCodec.parseElement('56S0 A295270452') as BtElement).kind, BtKind.line);
      expect((BtCodec.parseElement('90R0 1001000505OID') as BtElement).kind, BtKind.rfid);
      expect((BtCodec.parseElement('85K0 1004250202') as BtElement).kind, BtKind.text);
    });

    test('BT header mirrorPoint / tagWidth', () {
      final doc = Pectab.parse('BTT1039~H0642270=#02C0 1004250202#') as BtDocument;
      expect(doc.version, '1039');
      expect(doc.tagWidth10, 642);
      expect(doc.mirrorPointMm, 270);
      expect(doc.continuationChar, '~');
      expect(doc.elemRefChar, '=');
    });

    test('hex item numbers', () {
      expect(BtCodec.parseElement('A1C0 1175150201=85'), isA<BtElement>());
      expect(BtCodec.parseElement('FFC0 1001010201'), isA<BtElement>());
    });
  });

  group('orientation table (every code)', () {
    const left = '12345678';
    const centre = 'ABCDEFGH';
    const right = 'IJKLMNOP';
    const rotations = [0, 0, 90, 90, 180, 180, 270, 270];
    const wob = [false, true, false, true, false, true, false, true];

    void expectOrient(String code, int rot, bool black, BtAlign align) {
      final e = BtCodec.parseElement('02C0 ${code}004250202') as BtElement;
      expect(e.orientCode, code, reason: code);
      expect(e.orient.rotationDeg, rot, reason: code);
      expect(e.orient.whiteOnBlack, black, reason: code);
      expect(e.orient.align, align, reason: code);
    }

    test('1–8 left', () {
      for (var i = 0; i < 8; i++) {
        expectOrient(left[i], rotations[i], wob[i], BtAlign.left);
      }
    });

    test('A–H centre', () {
      for (var i = 0; i < 8; i++) {
        expectOrient(centre[i], rotations[i], wob[i], BtAlign.centre);
      }
    });

    test('I–P right', () {
      for (var i = 0; i < 8; i++) {
        expectOrient(right[i], rotations[i], wob[i], BtAlign.right);
      }
    });

    test('preserves E vs 5 (no normalisation)', () {
      final e5 = BtCodec.parseElement('73C0 5433480202P/W') as BtElement;
      expect(e5.orientCode, '5');
      final eE = BtCodec.parseElement('73C0 E433480202P/W') as BtElement;
      expect(eE.orientCode, 'E');
      expect(eE.orient.rotationDeg, 180);
      eE.markDirty();
      expect(eE.serializeEdited(), contains('E'));
      expect(eE.serializeEdited(), isNot(contains('C05')));
    });
  });

  group('document', () {
    test('manual BT classifies and round-trips', () {
      final doc = Pectab.parse(manualBt) as BtDocument;
      expect(doc.serialize(), manualBt);
      expect(doc.elements.whereType<UnknownElement>(), isEmpty);
      expect(doc.elements.whereType<BtElement>().length, doc.elements.length);
    });

    test('dirty rewrite only changes that element', () {
      final doc = Pectab.parse(manualBt) as BtDocument;
      final e = doc.elements.cast<BtElement>().firstWhere((e) => e.itemNo == '02');
      e.alongMm = 5;
      e.markDirty();
      final out = doc.serialize();
      expect(out, isNot(manualBt));
      expect(out, contains('02C0 1005250202#'));
      expect(out.split('#').where((s) => s == 'FFC0 1001010201').length, 2);
    });
  });
}
