import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

import 'fixtures/manual_samples.dart';

void main() {
  group('BP tokenizer', () {
    test('manual BP sample tokenizes with SPEC header', () {
      final doc = PectabTokenizer.tokenize(manualBp);
      expect(doc, isA<BpDocument>());
      final bp = doc as BpDocument;
      expect(bp.header, 'PT##?S9N#@;#TICKT#CHKIN#BOARD#01011101#');
      expect(bp.tableId, 'S');
      expect(bp.emd, isFalse);
      expect(bp.trailing, isNull);
      expect(bp.serialize(), manualBp);
    });

    test('BP elements keep verbatim sources and item numbers', () {
      final bp = PectabTokenizer.tokenize(manualBp) as BpDocument;
      expect(bp.elements, isNotEmpty);
      expect(bp.elements.every((e) => e is UnknownElement), isTrue);
      expect(bp.elements.first.source, '0330G15');
      expect(bp.elements.first.itemNo, '03');
      final fa = bp.elements.firstWhere((e) => e.itemNo == 'FA');
      expect(fa.source, 'FAB6Q252033');
      final reserved = bp.elements.where((e) => e.itemNo == '50').single;
      expect(reserved.source, '5010');
    });

    test('EMD header sets emd flag', () {
      const emd = 'PT##?E9N#@;#TICKT#CHKIN#BOARD#01011101#0330G15#';
      final bp = PectabTokenizer.tokenize(emd) as BpDocument;
      expect(bp.emd, isTrue);
      expect(bp.tableId, 'E');
      expect(bp.serialize(), emd);
    });
  });

  group('BT tokenizer', () {
    test('manual BTT1039 sample tokenizes', () {
      final doc = PectabTokenizer.tokenize(manualBt);
      expect(doc, isA<BtDocument>());
      final bt = doc as BtDocument;
      expect(bt.header, 'BTT1039~H0642172=#');
      expect(bt.version, '1039');
      expect(bt.kind, BtTagKind.standard);
      expect(bt.serialize(), manualBt);
    });

    test('BT keeps line elements, mirrors, aliases and duplicates', () {
      final bt = PectabTokenizer.tokenize(manualBt) as BtDocument;
      final sources = bt.elements.map((e) => e.source).toList();
      expect(sources, contains('56S0 A295270452'));
      expect(sources, contains('51C0M2211070302'));
      expect(sources, contains('D5C0 5430410303=89'));
      expect(sources.where((s) => s == 'FFC0 1001010201').length, 2);
      expect(bt.elements.where((e) => e.itemNo == 'FF').length, 2);
    });

    test('limited-release and cabin versions', () {
      expect(
        (PectabTokenizer.tokenize('BTT1139~H0642172=#01C0 1004110202#') as BtDocument).kind,
        BtTagKind.limitedRelease,
      );
      expect((PectabTokenizer.tokenize('BTT1239~H0642172=#01C0 1004110202#') as BtDocument).kind, BtTagKind.cabin);
    });
  });

  group('Template tokenizer', () {
    test('BOX / LINE template samples round-trip', () {
      expect(PectabTokenizer.tokenize(manualTemplateBox).serialize(), manualTemplateBox);
      expect(PectabTokenizer.tokenize(manualTemplateLine).serialize(), manualTemplateLine);
      final doc = PectabTokenizer.tokenize(manualTemplateBox) as TemplateDocument;
      expect(doc.tableId, '01');
      expect(doc.elements.single.source, '01B0230600150105000100000');
    });
  });

  group('round-trip', () {
    test('serialize(tokenize(s)) == s for every manual sample', () {
      for (final s in [manualBp, manualBt, manualTemplateBox, manualTemplateLine]) {
        expect(PectabTokenizer.tokenize(s).serialize(), s, reason: s.substring(0, 24));
      }
    });

    test('preserves spaces and does not trim', () {
      const s = 'BTT1039~H0642172=#02C0 1004250202#';
      final el = (PectabTokenizer.tokenize(s) as BtDocument).elements.single;
      expect(el.source, '02C0 1004250202');
      expect(el.source, contains(' '));
    });

    test('empty body after header', () {
      const s = 'BTT1039~H0642172=#';
      final bt = PectabTokenizer.tokenize(s) as BtDocument;
      expect(bt.elements, isEmpty);
      expect(bt.serialize(), s);
    });
  });
}
