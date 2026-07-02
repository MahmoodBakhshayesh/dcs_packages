# dcs_cupps

Socket/XML CUPPS communication utilities for Flutter DCS applications.

## Install (git)

```yaml
dependencies:
  dcs_cupps:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_cupps
      ref: main
```

This package provides a clean, testable core for talking to a CUPPS platform,
authenticating the DCS application, discovering platform devices, opening device
sockets, sending XML requests, tracking platform/device status, and collecting
structured logs.

## Features

- CUPPS frame codec for the `0100` + hex-length socket header.
- Robust fragmented/batched socket message decoding.
- XML builders/parsers for platform negotiation, authentication, device query,
  device acquire, lock/unlock, release, AEA commands, print requests, and stop
  command responses.
- Request correlation by `messageID` with timeouts and pending-request cleanup.
- Separate platform and per-device socket sessions.
- Visible lifecycle states for platform and devices through broadcast streams.
- Structured logs for lifecycle, socket, protocol, platform, and device events.
- Optional JSONL file log sink supplied by the application.
- Injectable transport for simulators and tests.
- Generated PNG status icons for CUPPS device types `bp`, `bt`, `bc`, `be`,
  `oc`, `ms`, `pr`, `bg`, `dd`, `zl`, and `zi`.

## Getting started

Add the package to the DCS application and create a `CuppsClient`. The package
does not depend on GetX, Riverpod, or app-specific UI code; wire its streams into
your state management layer.

## Usage

```dart
final logger = CuppsLogger(
  sinks: [
    CuppsFileLogSink(directory: Directory('C:/DCS/cupps_logs')),
  ],
);

final client = CuppsClient(logger: logger);

client.platformStatus.listen((status) {
  debugPrint('CUPPS platform: ${status.state.name} - ${status.message}');
});

client.deviceStatuses.listen((statuses) {
  for (final status in statuses.values) {
    debugPrint('${status.device.name}: ${status.state.name}');
  }
});

await client.connect(
  endpoint: const CuppsEndpoint(host: '127.0.0.1', port: 4000),
  application: const CuppsApplicationInfo(
    airlineCode: 'ZZ',
    applicationName: 'DCS',
    applicationVersion: '1.0.0',
  ),
);

await client.authenticate();
await client.connectDevices();

final bp = client.devices
    .where((device) => device.type == CuppsDeviceType.boardingPassPrinter)
    .firstOrNull;

if (bp != null) {
  await bp.lock();
  final result = await bp.print('BOARDING PASS DATA');
  debugPrint(result.ok ? 'Printed' : 'Print failed: ${result.message}');
}
```

## Status assets

Status PNGs are packaged under `assets/images/icons/<device>/<device>_<status>.png`.
Use `CuppsStatusAssets.forDeviceStatus(status)` to resolve an icon for a live
`CuppsDeviceStatus`, then load it with `Image.asset(path, package: 'dcs_cupps')`.

Generated statuses are `natural`, `active`, `disconnect`, `in`, `locked`,
`data_available`, `printing`, `configuring`, `inuse`, `jammed`, `open`,
`paper_out`, and `failed`.

## Additional information

This is a fresh implementation intended to replace older singleton-style CUPPS
code. Keep airport/platform-specific XML rules in tests where possible, and add
simulator-backed tests before changing message formats or device state behavior.
