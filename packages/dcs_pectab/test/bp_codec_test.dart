import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

import 'fixtures/manual_samples.dart';

void main() {
  group('BpCodec text', () {
    test('single position medium', () {
      final e = BpCodec.parseElement('2305O07') as BpText;
      expect(e.itemNo, '23');
      expect(e.length, 5);
      expect(e.positions, [BpPos(row: 'O', col: 7)]);
      expect(e.style, BpStyle.medium);
    });

    test('multi-position small / bold', () {
      final small = BpCodec.parseElement('0705I26K54L') as BpText;
      expect(small.positions, [BpPos(row: 'I', col: 26), BpPos(row: 'K', col: 54)]);
      expect(small.style, BpStyle.small);

      final bold = BpCodec.parseElement('2605N06P57R') as BpText;
      expect(bold.positions, [BpPos(row: 'N', col: 6), BpPos(row: 'P', col: 57)]);
      expect(bold.style, BpStyle.bold);
    });

    test('FE/FF titles are text not barcode', () {
      final fe = BpCodec.parseElement('FE01R01') as BpText;
      expect(fe.length, 1);
      expect(fe.positions.single, BpPos(row: 'R', col: 1));
    });

    test('magstripe only + magstripe with position', () {
      final mag = BpCodec.parseElement('52101101') as BpText;
      expect(mag.magStripe, '1101');
      expect(mag.positions, isEmpty);
      final both = BpCodec.parseElement('03101101F48') as BpText;
      expect(both.magStripe, '1101');
      expect(both.positions.single, BpPos(row: 'F', col: 48));
    });
  });

  group('BpCodec reserved', () {
    test('length only — not printed', () {
      for (final s in ['5010', '5104', '5202', '0415', '0903', '1807']) {
        final e = BpCodec.parseElement(s);
        expect(e, isA<BpReserved>(), reason: s);
        expect((e as BpReserved).length, int.parse(s.substring(2, 4)));
      }
    });
  });

  group('BpCodec barcode', () {
    test('PDF417 without rotate', () {
      final e = BpCodec.parseElement('FAB6Q252033') as BpBarcode;
      expect(e.itemNo, 'FA');
      expect(e.type, BpBarcodeType.pdf417);
      expect(e.typeCode, '6');
      expect(e.pos, BpPos(row: 'Q', col: 25));
      expect(e.heightMm, 20);
      expect(e.ecc, 3);
      expect(e.hri, 3);
      expect(e.rotate180, isFalse);
    });

    test('rotate 180 (R after B)', () {
      final e = BpCodec.parseElement('FBBR6D012259') as BpBarcode;
      expect(e.rotate180, isTrue);
      expect(e.rotationDeg, 180);
      expect(e.typeCode, '6');
      expect(e.pos, BpPos(row: 'D', col: 1));
      expect(e.heightMm, 22);
      expect(e.ecc, 5);
      expect(e.hri, 9);
    });

    test('rotate 90 (L after B)', () {
      final e = BpCodec.parseElement('FABL6Q252033') as BpBarcode;
      expect(e.rotationDeg, 90);
      expect(e.rotate180, isFalse);
      expect(e.serializeEdited(), 'FABL6Q252033');
    });

    test('type table', () {
      // after B: type(1)+row(1)+col(2)+hh(2)+ecc(1)+hri(1) = 8 chars
      expect((BpCodec.parseElement('FAB1A010101') as BpBarcode).type, BpBarcodeType.oneD1);
      expect((BpCodec.parseElement('FAB2A010101') as BpBarcode).type, BpBarcodeType.oneD2);
      expect((BpCodec.parseElement('FAB5A010101') as BpBarcode).type, BpBarcodeType.qr);
      expect((BpCodec.parseElement('FAB6A010101') as BpBarcode).type, BpBarcodeType.pdf417);
      expect((BpCodec.parseElement('FAB9A010101') as BpBarcode).type, BpBarcodeType.other);
    });
  });

  group('dirty serialize', () {
    test('edited text rewrites only when dirty', () {
      final e = BpCodec.parseElement('2305O07') as BpText;
      expect(e.dirty, isFalse);
      expect(e.source, '2305O07');
      e.positions = [BpPos(row: 'O', col: 8)];
      e.markDirty();
      expect(e.serializeEdited(), '2305O08');
    });

    test('barcode serializeEdited round-trips fields', () {
      final e = BpCodec.parseElement('FAB6Q252033') as BpBarcode;
      e.markDirty();
      expect(e.serializeEdited(), 'FAB6Q252033');
      e.rotate180 = true;
      expect(e.serializeEdited(), 'FABR6Q252033');
    });
  });

  group('document parse', () {
    test('manual BP classifies known forms and round-trips', () {
      final doc = Pectab.parse(manualBp) as BpDocument;
      expect(doc.serialize(), manualBp);
      expect(doc.elements.whereType<BpBarcode>().length, 1);
      expect(doc.elements.whereType<BpReserved>(), isNotEmpty);
      expect(doc.elements.whereType<BpText>(), isNotEmpty);
      expect(doc.elements.whereType<UnknownElement>(), isEmpty);
    });

    test('table: each manual BP element form', () {
      final doc = Pectab.parse(manualBp) as BpDocument;
      final byNo = {for (final e in doc.elements) e.itemNo: e};
      expect(byNo['03'], isA<BpText>());
      expect(byNo['04'], isA<BpReserved>());
      expect(byNo['07'], isA<BpText>());
      expect((byNo['07'] as BpText).style, BpStyle.small);
      expect(byNo['26'], isA<BpText>());
      expect((byNo['26'] as BpText).style, BpStyle.bold);
      expect(byNo['FA'], isA<BpBarcode>());
      expect(byNo['FE'], isA<BpText>());
      expect(byNo['50'], isA<BpReserved>());
    });
  });
}
