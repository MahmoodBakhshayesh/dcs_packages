# Changelog

## 0.2.1

- iOS: cast TCP port substring to `NSString` before `integerValue` (Xcode 16 / modern Clang).

## 0.2.0

- Discovery: `ZebraPrinterDescriptor` adds `rssi`, `paired`, and `isMobileModel` (ZQ / iMZ / ZR); `ZebraClient.discoverStream` emits results as they arrive.
- Pairing: Android `pair` / `unpair` / `bondedPrinters` via Bluetooth bond APIs; iOS `pairedAccessories` and `ZebraPairingResult.openSystemSettings`.
- Printer actions: `calibrate`, `printConfigurationLabel`, `printTestLabel`, darkness / speed SGD getters & setters, `batteryPercent`.
- Batch printing: `printBatch` stream with per-job progress, `cancelBatch`, and `retryFailedJobs`.
- Permissions: `ensureBluetoothPermissions` (Android 12+ SCAN/CONNECT, legacy location); README documents manifest / Info.plist (`com.zebra.rawport`, MFi note).

## 0.1.0

- Initial `dcs_zebra` package: TCP printing on all platforms, BT/USB where Link-OS supports it.
- CUPPS-parity status icons, logger, and downloadable JSONL logs.
- Android (JAR), iOS (xcframework/MFi), Windows (TCP + best-effort BT/USB), macOS (TCP).
