/// Certification checklist contracts for DCS integrations.
library;

import 'package:dcs_common/dcs_common.dart';

typedef DcsCertificationPredicate = bool Function(Map<String, Object?> context);

class DcsCertificationCheck {
  const DcsCertificationCheck({
    required this.id,
    required this.module,
    required this.title,
    required this.evaluate,
    this.blocking = true,
  });

  final String id;
  final DcsPackageModule module;
  final String title;
  final DcsCertificationPredicate evaluate;
  final bool blocking;
}

class DcsCertificationResult {
  const DcsCertificationResult({
    required this.check,
    required this.passed,
    this.message = '',
  });

  final DcsCertificationCheck check;
  final bool passed;
  final String message;

  bool get blocksRelease => !passed && check.blocking;
}

class DcsCertificationPlan {
  const DcsCertificationPlan({required this.checks});

  final List<DcsCertificationCheck> checks;

  List<DcsCertificationResult> evaluate(Map<String, Object?> context) {
    return checks
        .map(
          (check) => DcsCertificationResult(
            check: check,
            passed: check.evaluate(context),
          ),
        )
        .toList(growable: false);
  }
}

class DcsStandardCertificationChecks {
  const DcsStandardCertificationChecks._();

  static DcsCertificationCheck endpointConfigured({
    required String id,
    required DcsPackageModule module,
    required String contextKey,
  }) {
    return DcsCertificationCheck(
      id: id,
      module: module,
      title: '$contextKey endpoint is configured',
      evaluate: (context) {
        final value = context[contextKey];
        return value is DcsEndpoint && value.isValid;
      },
    );
  }
}
