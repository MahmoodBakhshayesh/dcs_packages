# dcs_zebra

Zebra Link-OS printer client for Flutter DCS applications. Network (TCP) printing works on **Windows, Android, iOS, and macOS**. Bluetooth / USB use platform SDKs where Zebra provides them.

Print payloads are **ZPL** (or CPCL/raw) supplied by the backend — this package does not convert AEA.

## Install (git)

```yaml
dependencies:
  dcs_zebra:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_zebra
      ref: main
```

## Capability matrix

| Platform | TCP/network | Bluetooth | USB |
|----------|-------------|-----------|-----|
| Android | Dart TCP + Link-OS JAR | Classic + BLE | OTG via Link-OS |
| iOS | Dart TCP + Link-OS xcframework | MFi only | Not supported by Zebra iOS SDK |
| Windows | Dart TCP | Discovery of paired/nearby BT (best-effort); print via TCP preferred | Not available without Zebra Windows driver stack |
| macOS | Dart TCP | Not available (no macOS Link-OS SDK) | Not available |

Default TCP ports: **9100** (ZPL), **6101** (CPCL), **9200** (status).

## Features

- `ZebraClient` / `ZebraPrinter` lifecycle aligned with CUPPS device usage
- Status streams, hardware flags (paper out, head open, paused, …)
- SGD get/set and `~HS` host-status parsing over TCP
- Structured `ZebraLogger` + JSONL file sink + `DcsStandardLogStore` bridge
- Status icons for boarding-pass / bag-tag roles (`bp` / `bt`) matching CUPPS visual statuses

## Usage

```dart
final logger = ZebraLogger(
  sinks: [ZebraFileLogSink(directory: Directory('C:/DCS/zebra_logs'))],
);

final client = ZebraClient(logger: logger);

final bp = await client.connectTcp(
  host: '192.168.1.50',
  role: ZebraPrinterRole.boardingPass,
  name: 'ZQ620-BP',
);

await bp.printZpl(r'''
^XA
^FO50,50^A0N,40,40^FDBoarding Pass^FS
^XZ
''');

final status = await bp.queryStatus();
debugPrint(status.hardwareStatusLabel);
```

### Bluetooth / USB (Android / iOS)

```dart
final caps = await client.platformCapabilities();
final found = await client.discover(types: [
  if (caps['bluetooth'] == true) ZebraConnectionType.bluetooth,
  if (caps['usb'] == true) ZebraConnectionType.usb,
]);

for (final d in found) {
  final printer = await client.connectDescriptor(
    d.copyWith(role: ZebraPrinterRole.bagTag),
  );
  await printer.printZpl(zplFromBackend);
}
```

### Status assets

```dart
Image.asset(
  ZebraStatusAssets.forPrinterStatus(status),
  package: ZebraStatusAssets.package,
);
```

### iOS setup notes

Add External Accessory protocols for your Zebra MFi models to the app `Info.plist` (`UISupportedExternalAccessoryProtocols`), and ensure Bluetooth permissions strings are present. USB is not supported by the Zebra iOS SDK.

### License note

Link-OS SDK binaries under `sdks/` and bundled into `android/libs` / `ios/Frameworks` are subject to Zebra’s Development Tool License. Redistribute only as integrated into your application.

## SDKs vendored in this package

- Android Link-OS **2.16.5518** (`android/libs`)
- iOS Link-OS **1.6.1158** (`ios/Frameworks/ZSDK_API.xcframework`)
- Optional local reference copies under `sdks/Link-OS_SDK/` (gitignored): only Android/iOS `lib` folders — demos, docs, print-station apps, and PC/.NET trees are not kept (re-download from Zebra if needed)
