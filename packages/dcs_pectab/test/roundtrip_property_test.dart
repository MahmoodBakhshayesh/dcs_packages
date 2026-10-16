import 'dart:math';

import 'package:dcs_pectab/dcs_pectab.dart';
import 'package:test/test.dart';

import 'fixtures/manual_samples.dart';

void main() {
  group('round-trip property', () {
    final samples = <String>[
      manualBp,
      manualBt,
      manualTemplateBox,
      manualTemplateLine,
      // DCS-style variants
      'PT##?A9N#@;#TICKT#CHKIN#BOARD#01011101#0330G15#FAB6Q252033#',
      'BTT1050~H0642172=#02C0 1004250202#03B1 A007260441#',
      'BTT1139~H0000000=#85C1 5230430201#',
      'BTT1239~H0000000=#71C0 1004030202#',
      aeaBoxExample,
      aeaLineExample,
    ];

    test('manual + DCS-style fixtures: parse → serialize == input', () {
      for (final s in samples) {
        expect(Pectab.parse(s).serialize(), s, reason: s.length > 40 ? s.substring(0, 40) : s);
      }
    });

    test('1000 fuzzed streams round-trip', () {
      final rng = Random(42);
      var failures = 0;
      for (var i = 0; i < 1000; i++) {
        final s = _fuzz(rng, i);
        final out = Pectab.parse(s).serialize();
        if (out != s) {
          failures++;
          if (failures <= 3) {
            fail('fuzz #$i diverged:\n  in:  $s\n  out: $out');
          }
        }
      }
      expect(failures, 0);
    });
  });
}

String _fuzz(Random rng, int i) {
  // Mix structured documents with random #-separated bodies so unknowns stay verbatim.
  final kind = i % 5;
  if (kind == 0) {
    return _fuzzBp(rng);
  }
  if (kind == 1) {
    return _fuzzBt(rng);
  }
  if (kind == 2) {
    return _fuzzTemplate(rng);
  }
  // Raw / junk segments (still #-separated) — tokenizer as RawDocument or BT/BP if prefixed.
  if (kind == 3) {
    final n = 1 + rng.nextInt(8);
    final parts = List.generate(n, (_) => _randSeg(rng));
    return '${parts.join('#')}#';
  }
  // Start from a manual sample and splice a random segment.
  final base = rng.nextBool() ? manualBp : manualBt;
  final insert = _randSeg(rng);
  final cut = base.indexOf('#', rng.nextInt(base.length - 1)) + 1;
  return '${base.substring(0, cut)}$insert#${base.substring(cut)}';
}

String _fuzzBp(Random rng) {
  final table = 'SA1Z'[rng.nextInt(4)];
  final emd = rng.nextBool() ? 'S9' : 'E9';
  // When table is used with S9/E9: ?S9N or ?E9N style — keep simple ?${table}9N
  final header = 'PT##?${table}9N#@;#TICKT#CHKIN#BOARD#01011101#';
  final els = <String>[for (var k = 0; k < 1 + rng.nextInt(6); k++) _bpElement(rng)];
  return '$header${els.join('#')}#';
}

String _bpElement(Random rng) {
  final form = rng.nextInt(3);
  final item = rng.nextInt(0x50).toRadixString(16).padLeft(2, '0').toUpperCase();
  if (form == 0) {
    // reserved
    final len = rng.nextInt(30).toString().padLeft(2, '0');
    return '$item$len';
  }
  if (form == 1) {
    final len = (1 + rng.nextInt(20)).toString().padLeft(2, '0');
    final row = String.fromCharCode(65 + rng.nextInt(18)); // A–R
    final col = (1 + rng.nextInt(70)).toString().padLeft(2, '0');
    final style = ['', 'L', 'R'][rng.nextInt(3)];
    return '$item$len$row$col$style';
  }
  // barcode
  final type = '12569'[rng.nextInt(5)];
  final row = String.fromCharCode(65 + rng.nextInt(18));
  final col = (1 + rng.nextInt(70)).toString().padLeft(2, '0');
  final rot = rng.nextBool() ? 'R' : '';
  return '${item}B$rot$type$row$col'
      '${rng.nextInt(40).toString().padLeft(2, '0')}'
      '${rng.nextInt(10)}'
      '${1 + rng.nextInt(3)}';
}

String _fuzzBt(Random rng) {
  final ver = ['1039', '1050', '1139', '1239'][rng.nextInt(4)];
  final header = 'BTT$ver~H${rng.nextInt(1 << 20).toRadixString(16).padLeft(7, '0')}=#';
  final els = [for (var k = 0; k < 1 + rng.nextInt(8); k++) _btElement(rng)];
  return '$header${els.join('#')}#';
}

String _btElement(Random rng) {
  final item = rng.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase();
  final kind = 'CBISL'[rng.nextInt(5)];
  final variant = rng.nextInt(2).toString();
  final mirror = rng.nextBool();
  final orients = '12345678ABCDEFGHIJKLMNOP';
  final o = orients[rng.nextInt(orients.length)];
  final mid = mirror ? 'M' : ' ';
  final geo =
      '${rng.nextInt(500).toString().padLeft(3, '0')}'
      '${rng.nextInt(50).toString().padLeft(2, '0')}'
      '${(1 + rng.nextInt(9)).toString().padLeft(2, '0')}'
      '${(1 + rng.nextInt(5)).toString().padLeft(2, '0')}';
  final tailKind = rng.nextInt(3);
  final tail = tailKind == 0
      ? ''
      : tailKind == 1
      ? '=${rng.nextInt(100).toString().padLeft(2, '0')}'
      : ['VIA:', 'P/W', 'XH', 'TO:'][rng.nextInt(4)];
  return '$item$kind$variant$mid$o$geo$tail';
}

String _fuzzTemplate(Random rng) {
  final id = rng.nextInt(20).toString().padLeft(2, '0');
  final item = rng.nextInt(20).toString().padLeft(2, '0');
  if (rng.nextBool()) {
    final body =
        'B'
        '${rng.nextInt(400).toString().padLeft(4, '0')}'
        '${rng.nextInt(400).toString().padLeft(3, '0')}'
        '${rng.nextInt(200).toString().padLeft(3, '0')}'
        '${rng.nextInt(2000).toString().padLeft(4, '0')}'
        '${rng.nextInt(20).toString().padLeft(3, '0')}'
        '00000';
    return 'TT$id#$item$body#';
  }
  final body =
      'S'
      '${rng.nextInt(400).toString().padLeft(4, '0')}'
      '${rng.nextInt(400).toString().padLeft(3, '0')}'
      '${rng.nextInt(200).toString().padLeft(3, '0')}'
      '${rng.nextInt(2000).toString().padLeft(4, '0')}'
      '00000';
  return 'TT$id#$item$body#';
}

String _randSeg(Random rng) {
  const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ =/~';
  final n = 1 + rng.nextInt(24);
  return String.fromCharCodes([for (var i = 0; i < n; i++) alphabet.codeUnitAt(rng.nextInt(alphabet.length))]);
}
