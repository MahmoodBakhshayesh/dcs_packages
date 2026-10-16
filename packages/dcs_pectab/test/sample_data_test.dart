import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

void main() {
  test('BTP sample from SPEC §3', () {
    const s =
        'BTP103901#020000109681#030000109681#71ZZ#721212#7319JUL#74TORONTO#75YYZ#811/10#83Y#85JACOB MARINO#86YVR#892#';
    final d = PectabSampleParser.parse(s);
    expect(d.kind, 'BTP');
    expect(d.header, 'BTP103901#');
    expect(d['02'], '0000109681');
    expect(d['03'], '0000109681');
    expect(d['71'], 'ZZ');
    expect(d['85'], 'JACOB MARINO');
    expect(d['89'], '2');
  });

  test('CP sample from SPEC §3', () {
    const s = 'CP#1C01#01S#03BEATRICE FABBRI#04VANCOUVER#05TORONTO#06ZZ#071200#50PASSENGER#51FROM#FAM1BEATRICE FABBRI#';
    final d = PectabSampleParser.parse(s);
    expect(d.kind, 'CP');
    expect(d.header, 'CP#1C01#');
    expect(d['01'], 'S');
    expect(d['03'], 'BEATRICE FABBRI');
    expect(d['04'], 'VANCOUVER');
    expect(d['50'], 'PASSENGER');
    expect(d['FA'], 'M1BEATRICE FABBRI');
  });
}
