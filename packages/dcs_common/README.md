# dcs_common

Shared runtime contracts used across DCS packages and applications.

## Features

- Device, transport, and runtime state enums (`DcsDeviceKind`, `DcsTransportKind`, `DcsRuntimeState`)
- `DcsRuntimeComponent`, `DcsRuntimeStatus`, and `DcsRuntimeLogEvent` models
- `DcsStandardLogStore` for JSONL and human-readable operation logs on disk
- `DcsPackageModule` identifiers for cross-package diagnostics

## Install (git)

```yaml
dependencies:
  dcs_common:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_common
      ref: main
```

## Usage

```dart
import 'package:dcs_common/dcs_common.dart';

final status = DcsRuntimeStatus.now(
  component: const DcsRuntimeComponent(
    id: 'bp-1',
    label: 'Boarding Pass Printer',
    module: DcsPackageModule.cupps,
    deviceKind: DcsDeviceKind.boardingPassPrinter,
    transport: DcsTransportKind.cuppsPlatform,
  ),
  state: DcsRuntimeState.ready,
  message: 'Device ready',
);

final store = DcsStandardLogStore(rootDirectory: Directory('C:/DCS/logs'));
await store.writeBoth(
  DcsStandardLogEvent.now(
    module: DcsPackageModule.common,
    severity: DcsLogSeverity.info,
    operation: 'startup',
    message: 'Application started',
  ),
);
```

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages). Report issues on the [issue tracker](https://github.com/MahmoodBakhshayesh/dcs_packages/issues).
