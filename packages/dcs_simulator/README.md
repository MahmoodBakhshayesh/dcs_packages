# dcs_simulator

In-memory simulators for DCS devices and host adapters — useful for development and automated tests.

## Features

- `SimulatedDcsDevice` with mutable runtime status
- `SimulatedHostAdapter` with canned responses per message type

## Install (git)

```yaml
dependencies:
  dcs_simulator:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_simulator
      ref: main
```

## Usage

```dart
import 'package:dcs_simulator/dcs_simulator.dart';
import 'package:dcs_host/dcs_host.dart';

final adapter = SimulatedHostAdapter(
  responses: {DcsHostMessageType.checkIn: 'CHECKED IN'},
);

final response = await adapter.send(
  const DcsHostRequest(
    id: '1',
    type: DcsHostMessageType.checkIn,
    payload: 'PAYLOAD',
  ),
);
```

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages).
