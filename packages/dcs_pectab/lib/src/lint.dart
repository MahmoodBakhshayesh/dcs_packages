import 'catalog.dart';
import 'geometry.dart';
import 'model.dart';

enum PectabLintSeverity { error, warn }

final class PectabLintIssue {
  const PectabLintIssue({required this.severity, required this.message, this.itemNo, this.elementIndex});

  final PectabLintSeverity severity;
  final String message;
  final String? itemNo;
  final int? elementIndex;
}

/// Validation (ARCHITECTURE §5).
abstract final class PectabLint {
  static List<PectabLintIssue> analyze(PectabDocument doc) {
    final out = <PectabLintIssue>[];
    if (doc.header.trim().isEmpty) {
      out.add(const PectabLintIssue(severity: PectabLintSeverity.error, message: 'header missing'));
    }

    final seen = <String, int>{};
    for (var i = 0; i < doc.elements.length; i++) {
      final e = doc.elements[i];
      final no = e.itemNo;
      if (no.isNotEmpty) {
        if (seen.containsKey(no)) {
          // duplicate item number — warn (BT allows intentional duplicates like FF)
          out.add(
            PectabLintIssue(
              severity: PectabLintSeverity.warn,
              message: 'duplicate item number $no',
              itemNo: no,
              elementIndex: i,
            ),
          );
        } else {
          seen[no] = i;
        }
      }

      switch (doc) {
        case BpDocument():
          _lintBp(e, i, out);
        case BtDocument():
          _lintBt(e, i, out, seen);
        default:
          break;
      }

      final bounds = PectabGeometry.boundsOf(e);
      if (bounds != null) {
        if (doc is BpDocument) {
          // Origin must sit on the coupon; extent overflow is warn (length past 70 covered separately).
          if (bounds.left < -0.01 || bounds.top < -0.01) {
            out.add(
              PectabLintIssue(
                severity: PectabLintSeverity.error,
                message: 'element outside BP canvas',
                itemNo: no,
                elementIndex: i,
              ),
            );
          } else if (bounds.right > PectabGeometry.bpWidthMm + 0.01 ||
              bounds.bottom > PectabGeometry.bpHeightMm + 0.01) {
            out.add(
              PectabLintIssue(
                severity: PectabLintSeverity.warn,
                message: 'element extent past BP canvas',
                itemNo: no,
                elementIndex: i,
              ),
            );
          }
        } else if (doc is BtDocument) {
          if (bounds.left < -0.01 || bounds.top < -0.01) {
            out.add(
              PectabLintIssue(
                severity: PectabLintSeverity.error,
                message: 'element outside BT canvas',
                itemNo: no,
                elementIndex: i,
              ),
            );
          } else if (bounds.top + bounds.height > PectabGeometry.btWidthMm + 0.01) {
            out.add(
              PectabLintIssue(
                severity: PectabLintSeverity.warn,
                message: 'element extent past BT canvas',
                itemNo: no,
                elementIndex: i,
              ),
            );
          }
        }
      }
    }
    // Alias targets must exist somewhere in the document.
    for (var i = 0; i < doc.elements.length; i++) {
      final e = doc.elements[i];
      if (e is BtElement && e.aliasOf != null && !seen.containsKey(e.aliasOf)) {
        out.add(
          PectabLintIssue(
            severity: PectabLintSeverity.error,
            message: '=NN alias to missing item ${e.aliasOf}',
            itemNo: e.itemNo,
            elementIndex: i,
          ),
        );
      }
    }
    return out;
  }

  static void _lintBp(PectabElement e, int i, List<PectabLintIssue> out) {
    if (e is BpText) {
      for (final p in e.positions) {
        final row = p.row.toUpperCase().codeUnitAt(0);
        if (row < 65 || row > 82) {
          out.add(
            PectabLintIssue(
              severity: PectabLintSeverity.error,
              message: 'BP row not A–R',
              itemNo: e.itemNo,
              elementIndex: i,
            ),
          );
        }
        if (p.col < 1 || p.col > 70) {
          out.add(
            PectabLintIssue(
              severity: PectabLintSeverity.error,
              message: 'BP column not 01–70',
              itemNo: e.itemNo,
              elementIndex: i,
            ),
          );
        }
        if (p.col + e.length - 1 > 70) {
          out.add(
            PectabLintIssue(
              severity: PectabLintSeverity.warn,
              message: 'length × columns runs past 70',
              itemNo: e.itemNo,
              elementIndex: i,
            ),
          );
        }
      }
      final cat = PectabCatalog.bpByItem(e.itemNo);
      if (cat == null) {
        out.add(
          PectabLintIssue(
            severity: PectabLintSeverity.warn,
            message: 'item not in catalog',
            itemNo: e.itemNo,
            elementIndex: i,
          ),
        );
      } else if (cat.maxLength != null && e.length < cat.maxLength!) {
        out.add(
          PectabLintIssue(
            severity: PectabLintSeverity.warn,
            message: 'length below catalog max (${cat.maxLength})',
            itemNo: e.itemNo,
            elementIndex: i,
          ),
        );
      }
    } else if (e is BpBarcode) {
      // ok
    } else if (e is UnknownElement && e.itemNo.isNotEmpty) {
      if (PectabCatalog.bpByItem(e.itemNo) == null) {
        out.add(
          PectabLintIssue(
            severity: PectabLintSeverity.warn,
            message: 'item not in catalog',
            itemNo: e.itemNo,
            elementIndex: i,
          ),
        );
      }
    }
  }

  static void _lintBt(PectabElement e, int i, List<PectabLintIssue> out, Map<String, int> seen) {
    if (e is! BtElement) return;
    final hex = int.tryParse(e.itemNo, radix: 16);
    if (hex != null && hex > 0xFF) {
      out.add(
        PectabLintIssue(
          severity: PectabLintSeverity.error,
          message: 'BT hex item > FF',
          itemNo: e.itemNo,
          elementIndex: i,
        ),
      );
    }
    // alias targets validated in a second pass
    if (PectabCatalog.btByItem(e.itemNo) == null) {
      out.add(
        PectabLintIssue(
          severity: PectabLintSeverity.warn,
          message: 'item not in catalog',
          itemNo: e.itemNo,
          elementIndex: i,
        ),
      );
    }
  }
}
