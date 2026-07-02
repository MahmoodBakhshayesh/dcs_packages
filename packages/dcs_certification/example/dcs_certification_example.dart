import 'package:dcs_certification/dcs_certification.dart';
import 'package:dcs_common/dcs_common.dart';

void main() {
  final plan = DcsCertificationPlan(
    checks: [
      DcsStandardCertificationChecks.endpointConfigured(
        id: 'CUTE-ENDPOINT',
        module: DcsPackageModule.cute,
        contextKey: 'cuteEndpoint',
      ),
    ],
  );
  final results = plan.evaluate({
    'cuteEndpoint': const DcsEndpoint(host: '127.0.0.1', port: 350),
  });
  print('Passed: ${results.every((result) => result.passed)}');
}
