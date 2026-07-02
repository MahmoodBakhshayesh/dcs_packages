# dcs_device_util

Reliable desktop device utilities for Flutter DCS applications.

## Install (git)

```yaml
dependencies:
  dcs_device_util:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_device_util
      ref: main
```

The package helps departure control system applications discover configured
reader and printer devices, recognize the right COM/USB-backed ports, save
configuration, retry failed connections, monitor connection health, reconnect
when possible, and update UI from live status streams.

## Features

- Configurable reader, printer, and unknown device profiles.
- Serial/COM discovery and connection through `flutter_libserialport`.
- Matcher rules for port name, manufacturer, product name, serial number,
  vendor ID, product ID, and custom metadata.
- Persisted configuration through `SharedPreferencesDcsConfigStore`.
- Retry policy with exponential backoff.
- Heartbeat-based health monitoring and optional auto reconnect.
- Queued request/response commands for devices that reply one command at a time.
- Response classification: `ok`, `error`, `unknown`, and `timeout`.
- Quiet-window response completion and optional STX/ETX framing with DLE escaping.
- Optional structured logging through `DcsLogger`.
- Bundled PNG status images for printer, reader, and generic USB/COM devices.
- Controller-bound UI helpers for status images, lists, cards, grids, banners,
  and custom status builders.

## Getting started

Add the package to a Flutter desktop application and create a
`DcsDeviceController` with your reader and printer profiles.

On Windows, COM ports are discovered with `flutter_libserialport`. For USB
printers that are exposed as COM/virtual serial devices, configure them as
serial profiles. For direct operating-system printer queues, add a custom
`DcsDeviceAdapter`.

## Usage

```dart
final controller = DcsDeviceController(
  configStore: const SharedPreferencesDcsConfigStore(),
  initialConfig: const DcsDeviceConfig(
    profiles: [
      DcsDeviceProfile(
        id: 'boarding-reader',
        label: 'Boarding Reader',
        kind: DcsDeviceKind.reader,
        matcher: DcsDeviceMatcher(
          portName: 'COM7',
          productName: 'Reader',
        ),
      ),
      DcsDeviceProfile(
        id: 'bag-printer',
        label: 'Bag Tag Printer',
        kind: DcsDeviceKind.printer,
        serialOptions: DcsSerialOptions(
          baudRate: 9600,
          flowControl: DcsSerialFlowControl.none,
        ),
        matcher: DcsDeviceMatcher(
          manufacturer: 'Zebra',
        ),
      ),
    ],
  ),
  logger: (event) {
    // Wire this to your application logger if needed.
    debugPrint('[${event.level.name}] ${event.message}');
  },
);

await controller.start();

final response = await controller.sendTextRequest(
  'boarding-reader',
  'AV',
  options: const DcsDeviceRequestOptions(
    timeout: Duration(seconds: 2),
    quietWindow: Duration(milliseconds: 150),
    framed: true,
  ),
);

if (response.isOk) {
  debugPrint('Reader replied: ${response.text}');
}
```

Use the included widget for a quick operator-facing status panel:

```dart
DcsDeviceControllerStatusList(controller: controller)
```

For dashboard screens, use the grid and summary banner:

```dart
Column(
  children: [
    DcsDeviceStatusSummaryBanner(controller: controller),
    const SizedBox(height: 16),
    DcsDeviceStatusGrid(controller: controller, crossAxisCount: 3),
  ],
)
```

Show only the standalone packaged status image:

```dart
DcsDeviceStatusImage(
  kind: DcsDeviceKind.printer,
  state: DcsDeviceConnectionState.connected,
  size: 72,
)
```

The built-in images are mapped as:

- `connected` and `available`: ready/green.
- `discovering`, `connecting`, `retrying`, and `degraded`: warning/orange.
- `failed`: error/red.
- `disconnected` and `unconfigured`: offline/gray.

## Request and response devices

Many DCS devices work as request/response endpoints: send one command, wait for
`OK`, `ERR`, a device-specific payload, or a timeout, then send the next command.
Use `sendTextRequest` or `sendRequest` for this pattern. Requests are serialized
per device profile so responses do not overlap.

By default, responses containing `OK`, `EPOK`, or `ESOK` are classified as
`ok`; responses containing `ERR`, `ERROR`, or `NOK` are classified as `error`;
non-empty responses are `unknown`; and missing responses are `timeout`.

Provide a custom classifier for device-specific protocols:

```dart
final response = await controller.sendTextRequest(
  'boarding-reader',
  'AV',
  options: DcsDeviceRequestOptions(
    classifier: (bytes, text) {
      final normalized = text.toUpperCase();
      if (normalized.startsWith('HDCAVOK')) {
        return DcsDeviceResponseStatus.ok;
      }
      if (normalized.startsWith('HDCAVERR')) {
        return DcsDeviceResponseStatus.error;
      }
      return bytes.isEmpty
          ? DcsDeviceResponseStatus.timeout
          : DcsDeviceResponseStatus.unknown;
    },
  ),
);
```

Enable `framed: true` when the device wraps payloads with `STX`/`ETX`. The queue
will remove framing bytes and unescape `DLE` before classification.

## Custom adapters

Implement `DcsDeviceAdapter` when a device is not represented as a serial port,
for example a Windows printer queue or a vendor SDK device. The controller will
still handle profile matching, retries, status updates, logging, health checks,
and reconnect behavior.

## Reliability notes

Connection reliability depends on deterministic profile matchers. Prefer stable
properties such as USB vendor/product IDs and serial numbers when available.
Port names like `COM7` are useful for fixed installations but can change after
driver updates or when the device is connected to a different USB socket.
