# dcs_host

Host messaging contracts for DCS integrations (MATIP, HTTP, vendor adapters).

## Features

- `DcsHostRequest` / `DcsHostResponse` message envelopes
- `DcsHostAdapter` interface for transport-specific implementations
- `DcsHostClient` with timeout handling

Depends on [dcs_common](https://github.com/MahmoodBakhshayesh/dcs_packages/tree/main/packages/dcs_common) for transport enums.

## Install (git)

```yaml
dependencies:
  dcs_host:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_host
      ref: main
```

## Usage

```dart
import 'package:dcs_host/dcs_host.dart';

class MyHostAdapter implements DcsHostAdapter {
  @override
  DcsTransportKind get transport => DcsTransportKind.hostApi;

  @override
  Future<DcsHostResponse> send(DcsHostRequest request) async {
    return DcsHostResponse(
      requestId: request.id,
      ok: true,
      payload: 'OK',
    );
  }
}

final client = DcsHostClient(MyHostAdapter());
```

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages).
