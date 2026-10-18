import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

import 'fixtures/manual_samples.dart';

Iterable<String> _loud(String raw) => PectabLint.analyze(Pectab.parse(raw))
    .where((i) => i.severity != PectabLintSeverity.info)
    .map((i) => '${i.itemNo} ${i.message}');

void main() {
  test('manual BP sample: only real problems are warnings / errors', () {
    // Items 08 (30 at E53), 12 (5 at K70) and 28 (15 at R58) really run past column 70 on the manual sample.
    expect(_loud(manualBp).toSet(), {
      '08 length × columns runs past 70',
      '12 length × columns runs past 70',
      '28 length × columns runs past 70',
    });
  });

  test('manual BT sample: no warnings / errors', () {
    final loud = _loud(manualBt);
    expect(loud, isEmpty, reason: loud.join('\n'));
  });
}
