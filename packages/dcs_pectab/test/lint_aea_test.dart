import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

import 'fixtures/manual_samples.dart';

void main() {
  group('lint', () {
    test('manual BP has no errors', () {
      final issues = PectabLint.analyze(Pectab.parse(manualBp));
      expect(issues.where((i) => i.severity == PectabLintSeverity.error), isEmpty);
    });

    test('flags BP column past 70', () {
      final doc = Pectab.parse('PT##?S9N#@;#TICKT#CHKIN#BOARD#01011101#0305A68#');
      final issues = PectabLint.analyze(doc);
      expect(issues.any((i) => i.message.contains('past 70')), isTrue);
    });

    test('flags missing header', () {
      final doc = RawDocument(
        header: '',
        elements: [UnknownElement(itemNo: '02', source: '02')],
      );
      expect(PectabLint.analyze(doc).any((i) => i.message.contains('header missing')), isTrue);
    });
  });

  group('AEA answer', () {
    test('PROK', () {
      final a = AeaAnswerDecoder.decode('..PROK');
      expect(a.code, 'PROK');
      expect(a.meaning, 'print ok');
    });

    test('ERR3=NN selects item', () {
      final doc = Pectab.parse(manualBp);
      final a = AeaAnswerDecoder.decode('ERR303=12', document: doc);
      expect(a.code, 'ERR3');
      expect(a.itemNo, '12');
      expect(a.elementIndexHint, isNotNull);
      expect(doc.elements[a.elementIndexHint!].itemNo, '12');
    });

    test('ERR8 with element', () {
      final doc = Pectab.parse(manualBt);
      final a = AeaAnswerDecoder.decode('ERR802', document: doc);
      expect(a.code, 'ERR8');
      expect(a.itemNo, '02');
      expect(a.elementIndexHint, isNotNull);
    });

    test('ERR6 PECTAB missing', () {
      expect(AeaAnswerDecoder.decode('ERR6').meaning, contains('PECTAB missing'));
    });
  });
}
