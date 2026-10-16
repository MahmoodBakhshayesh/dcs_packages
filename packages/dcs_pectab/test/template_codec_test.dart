import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

import 'fixtures/manual_samples.dart';

void main() {
  group('BOX', () {
    test('AEA example B0200240100050000500000', () {
      final e = TemplateCodec.parseElement(aeaBoxExample.replaceAll('#', '')) as BoxElement;
      expect(e.itemNo, '');
      expect(e.x10, 200);
      expect(e.y10, 240);
      expect(e.h10, 100);
      expect(e.l10, 500);
      expect(e.border10, 5);
      expect(e.reserved, '00000');
    });

    test('manual sample with item prefix', () {
      final e = TemplateCodec.parseElement('01B0230600150105000100000') as BoxElement;
      expect(e.itemNo, '01');
      expect(e.x10, 230);
      expect(e.y10, 600);
      expect(e.h10, 150);
      expect(e.l10, 1050);
      expect(e.border10, 1);
    });
  });

  group('LINE', () {
    test('AEA example (corrected 19-digit body)', () {
      final e = TemplateCodec.parseElement(aeaLineExample.replaceAll('#', '')) as LineElement;
      expect(e.x10, 200);
      expect(e.y10, 240);
      expect(e.h10, 50);
      expect(e.l10, 500);
      expect(e.reserved, '00000');
    });

    test('SPEC short example kept unknown (verbatim)', () {
      final e = TemplateCodec.parseElement(aeaLineExampleAsPrintedInSpec.replaceAll('#', ''));
      expect(e, isA<UnknownElement>());
    });

    test('manual sample', () {
      final e = TemplateCodec.parseElement('03S0001100006174000000') as LineElement;
      expect(e.itemNo, '03');
      expect(e.x10, 1);
      expect(e.y10, 100);
      expect(e.h10, 6);
      expect(e.l10, 1740);
    });
  });

  group('document', () {
    test('TT streams round-trip', () {
      for (final s in [manualTemplateBox, manualTemplateLine]) {
        final doc = Pectab.parse(s) as TemplateDocument;
        expect(doc.serialize(), s);
        expect(doc.elements, isNotEmpty);
        expect(doc.elements.first, anyOf(isA<BoxElement>(), isA<LineElement>()));
      }
    });
  });
}
