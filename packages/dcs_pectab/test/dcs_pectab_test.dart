import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

void main() {
  test('package exports a version marker', () {
    expect(dcsPectabVersion, startsWith('0.1.0'));
  });
}
