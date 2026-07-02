import 'package:dcs_common/dcs_common.dart';
import 'package:dcs_certification/dcs_certification.dart';
import 'package:test/test.dart';

void main() {
  group('certification plan', () {
    test('evaluates endpoint checks', () {
      final plan = DcsCertificationPlan(
        checks: [
          DcsStandardCertificationChecks.endpointConfigured(
            id: 'CUTE-001',
            module: DcsPackageModule.cute,
            contextKey: 'cuteEndpoint',
          ),
        ],
      );

      final results = plan.evaluate({
        'cuteEndpoint': const DcsEndpoint(host: '127.0.0.1', port: 350),
      });

      expect(results.single.passed, isTrue);
      expect(results.single.blocksRelease, isFalse);
    });
  });
}
