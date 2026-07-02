# dcs_certification

Certification checklist contracts for DCS common-use and hardware integrations.

## Features

- `DcsCertificationCheck` with blocking/non-blocking evaluation
- `DcsCertificationPlan` batch evaluation
- `DcsStandardCertificationChecks` helpers (e.g. endpoint configured)

## Install (git)

```yaml
dependencies:
  dcs_certification:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_certification
      ref: main
```

## Usage

```dart
import 'package:dcs_certification/dcs_certification.dart';
import 'package:dcs_common/dcs_common.dart';

final plan = DcsCertificationPlan(checks: [
  DcsStandardCertificationChecks.endpointConfigured(
    id: 'cupps-endpoint',
    module: DcsPackageModule.cupps,
    contextKey: 'cuppsEndpoint',
  ),
]);

final results = plan.evaluate({
  'cuppsEndpoint': const DcsEndpoint(host: '127.0.0.1', port: 4000),
});
```

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages).
