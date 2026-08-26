# dcs_cute_peripherals

CUTE workstation peripheral clients for Flutter DCS:

| Vendor | Transport | Package API |
|--------|-----------|-------------|
| **ARINC / MUSE** | Pure Dart TCP (PCP32 RQB) | `CutePeripheral.arinc` / `ArincClient` |
| **SITA** | Windows FFI → `xspmapi.dll` (CUTE/NT SDK **1.34**) | `CutePeripheral.sita` / `SitaClient` |
| **RESA** | Windows FFI → `crwnt_dm.dll` | `CutePeripheral.resa` / `ResaClient` |

This is separate from `dcs_cute` (MATIP host messaging) and `dcs_cupps` (CUPPS/ITPS XML).

## Install

```yaml
dependencies:
  dcs_cute_peripherals:
    path: ../dcs_cute_peripherals
    # or git path: packages/dcs_cute_peripherals
```

## ARINC (no vendor DLL)

```dart
final device = CutePeripheral.arinc(
  kind: CutePeripheralKind.atb,
  endpoint: const CutePeripheralEndpoint(host: '127.0.0.1', port: 50001),
  name: 'ATB1',
);
await device.open();
await device.lock();
await device.writeAea('QS');
await device.unlock();
await device.close();
```

Requires a reachable MUSE/PCP32 service on the CUTE workstation.

## SITA (Windows + `xspmapi.dll`)

Bindings match CUTE/NT SDK 1.34 `XSPMAPI.H` (sample `TSTPMAPI`).

```dart
final device = CutePeripheral.sita(
  identity: const CutePeripheralIdentity(
    kind: CutePeripheralKind.btp,
    name: 'BTP1',
    airlineCode: 'IR', // required: 2–3 letter designator configured in CUTENT\AIRLINES
  ),
);
await device.open();
await device.lock();
await device.writeAea('BT...AEA...');
await device.unlock(); // XSPMFlush(PM_FLUSHLOCK) — there is no XSPMUnlock
await device.flush();  // optional full flush
await device.close();
```

Helpers:

- `sitaGetConfiguredDevices()` / `sitaGetDeviceDescription(name)`
- `sitaNotifyApplicationState(airlineCode:, active:)`
- `kCuteNtSdkVersion` → `'1.34'`

### Workstation prerequisites (SDK setup)

1. Install CUTE/NT SDK 1.34; start **SITA Peripheral Manager** (`xswinpm.exe` / service).
2. Registry under `HKLM\SOFTWARE\SITAAPS\CUTENT\` (32-bit OS) or
   `HKLM\SOFTWARE\WOW6432Node\SITAAPS\CUTENT\` (64-bit OS).
3. Rename workstation key under `CUTENT\WORKSTATIONS` (10-char name).
4. Rename airline key under `AIRLINES` (e.g. `XS` → your 2-letter code).
5. Configure COM ports / devices; devices must be **COM** (or virtual COM) — USB-native is unsupported.
6. Validate with `TSTPMAPI` (Open with device name + airline code).

### Architecture note (critical)

CUTE typically installs a **32-bit** `xspmapi.dll` (WOW6432Node). A **64-bit** Flutter Windows
process cannot load a 32-bit DLL. For SITA peripherals you need a matching bitness host
(32-bit helper process, or a 64-bit PM DLL if your site provides one).

## RESA (Windows + `crwnt_dm.dll`)

```dart
final device = CutePeripheral.resa(
  identity: const CutePeripheralIdentity(
    kind: CutePeripheralKind.atb,
    name: 'BPP',
    order: 0,
  ),
);
await device.open();
await device.writeAea('QS');
await device.close();
```

Device type tokens: `RTE`, `BPP`, `BTP`, `DCP`, `BCD`.

## Shared contract

All vendors implement `CutePeripheral`:

- `open` / `close` / `dispose`
- `lock` / `unlock` / `flush`
- `write` / `writeAea`
- `read` / `queryStatus`
- `statusChanges` / `data` streams

## Notes

- SITA/RESA APIs throw `UnsupportedError` on non-Windows platforms.
- AEA command content (`PT`, `BT`, `QS`, PECTAB load, etc.) is the same family across vendors; only transport differs.
- Hardware certification still depends on the airport CUTE image and local device names/ports.
