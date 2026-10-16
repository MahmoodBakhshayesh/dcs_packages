import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

import 'fixtures/dcs_field_keys.dart';

void main() {
  test('every catalog dcsKey exists in DCS field-key lists', () {
    final missing = <String>[];
    for (final e in PectabCatalog.bp) {
      final k = e.dcsKey;
      if (k != null && !dcsBpFieldKeys.contains(k)) missing.add('BP ${e.itemNo}→$k');
    }
    for (final e in PectabCatalog.bt) {
      final k = e.dcsKey;
      if (k != null && !dcsBtFieldKeys.contains(k)) missing.add('BT ${e.itemNo}→$k');
    }
    expect(missing, isEmpty, reason: missing.join(', '));
  });

  test('SPEC core BP / BT item numbers are present', () {
    for (final no in ['03', '07', '23', 'FA', '50', '66']) {
      expect(PectabCatalog.bpByItem(no), isNotNull, reason: no);
    }
    for (final no in ['02', '03', '71', '85', '89', 'E0', 'F0']) {
      expect(PectabCatalog.btByItem(no), isNotNull, reason: no);
    }
  });

  test('item numbers unique within each catalog', () {
    expect(PectabCatalog.bp.map((e) => e.itemNo).toSet().length, PectabCatalog.bp.length);
    expect(PectabCatalog.bt.map((e) => e.itemNo).toSet().length, PectabCatalog.bt.length);
  });
}
