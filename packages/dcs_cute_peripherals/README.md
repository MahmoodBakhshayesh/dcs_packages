# dcs_cute_peripherals

CUTE workstation peripheral clients for Flutter DCS:

| Vendor | Transport | Package API |
|--------|-----------|-------------|
| **ARINC / MUSE** | Pure Dart TCP (PCP32 RQB) | `CutePeripheral.arinc` / `ArincClient` |
| **SITA** | Windows FFI → `xspmapi.dll` | `CutePeripheral.sita` / `SitaClient` |
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

```dart
final device = CutePeripheral.sita(
  identity: const CutePeripheralIdentity(
    kind: CutePeripheralKind.btp,
    name: 'BTP1',
    airlineCode: 'IR',
  ),
);
await device.open();
await device.lock();
await device.writeAea('BT...AEA...');
await device.close();
```

`xspmapi.dll` (and the SITA CUTE Peripheral Manager) must already be installed on the PC. Legacy `SitaCoreLibrary.dll` is not used by the live path.

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
- `lock` / `unlock`
- `write` / `writeAea`
- `read` / `queryStatus`
- `statusChanges` / `data` streams

## Notes

- SITA/RESA APIs throw `UnsupportedError` on non-Windows platforms.
- AEA command content (`PT`, `BT`, `QS`, PECTAB load, etc.) is the same family across vendors; only transport differs.
- Hardware certification still depends on the airport CUTE image and local device names/ports.
