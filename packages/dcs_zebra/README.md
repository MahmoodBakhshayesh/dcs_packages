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
      ref: dcs_zebra-v0.2.0
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
- Discovery with `rssi`, `paired`, `isMobileModel` (ZQ / iMZ / ZR) and `discoverStream`
- Android Bluetooth pair / unpair / bonded list; iOS paired MFi accessories
- Printer actions: calibrate (`~JC`), config label (`~WC`), test label, darkness / speed SGD, battery %
- Batch printing with per-job progress, cancel, and retry of failed jobs
- `ensureBluetoothPermissions()` for Android 12+ SCAN/CONNECT (legacy location)
- Status streams, hardware flags (paper out, head open, paused, …)
- SGD get/set and `~HS` host-status parsing over TCP
- Structured `ZebraLogger` + JSONL file sink + `DcsStandardLogStore` bridge
- Status icons for boarding-pass / bag-tag roles (`bp` / `bt`) matching CUPPS visual statuses

## Platform setup

### Android (`AndroidManifest.xml`)

The plugin declares these permissions; ensure the **host app** merge keeps them:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

Call `await client.ensureBluetoothPermissions()` before discovery on Android 12+ (SCAN / CONNECT) or older APIs (location for Classic discovery).

### iOS (`Info.plist`)

Add External Accessory protocols for your Zebra MFi models and Bluetooth usage strings:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.zebra.rawport</string>
  <!-- Add any additional Zebra protocol strings required for your models -->
</array>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connect to Zebra printers for boarding passes and bag tags.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Connect to Zebra printers for boarding passes and bag tags.</string>
```

**MFi whitelisting:** the iOS app’s bundle ID must be registered with Zebra for the Link-OS / MFi accessory protocols you use. Pairing itself is done in **Settings → Bluetooth**; `client.pair(...)` returns `ZebraPairingResult.openSystemSettings` so the UI can explain that. USB is not supported by the Zebra iOS SDK.

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

### Discovery stream (RSSI / paired / mobile)

```dart
await client.ensureBluetoothPermissions();

await for (final d in client.discoverStream(
  types: [ZebraConnectionType.bluetooth, ZebraConnectionType.bluetoothLe],
)) {
  debugPrint(
    '${d.displayName} rssi=${d.rssi} paired=${d.paired} mobile=${d.isMobileModel}',
  );
}
```

### Pairing

```dart
final result = await client.pair(descriptor);
if (result == ZebraPairingResult.openSystemSettings) {
  // iOS: show instructions to pair in Settings.
}
final bonded = await client.bondedPrinters();       // Android / Windows
final accessories = await client.pairedAccessories(); // iOS MFi (+ Android bonded)
```

### Printer actions & batch

```dart
await printer.calibrate();
await printer.printConfigurationLabel();
await printer.printTestLabel(text: 'Gate A12');
await printer.setDarkness(15);
await printer.setSpeed(4);
final battery = await printer.batteryPercent(); // null on many desktop models

await for (final progress in printer.printBatch(jobs, waitForReady: true)) {
  debugPrint('${progress.jobId} ${progress.state}');
}
printer.cancelBatch();
await for (final progress in printer.retryFailedJobs()) { /* … */ }
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

### License note

Link-OS SDK binaries under `sdks/` and bundled into `android/libs` / `ios/Frameworks` are subject to Zebra’s Development Tool License. Redistribute only as integrated into your application.

## SDKs vendored in this package

- Android Link-OS **2.16.5518** (`android/libs`)
- iOS Link-OS **1.6.1158** (`ios/Frameworks/ZSDK_API.xcframework`)
- Optional local reference copies under `sdks/Link-OS_SDK/` (gitignored): only Android/iOS `lib` folders — demos, docs, print-station apps, and PC/.NET trees are not kept (re-download from Zebra if needed)
