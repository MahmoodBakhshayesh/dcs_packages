## 0.2.0

- Align SITA `xspmapi.dll` bindings with CUTE/NT SDK **1.34** `XSPMAPI.H`
- Fix unlock: there is no `XSPMUnlock` — release via `XSPMFlush(PM_FLUSHLOCK)` (and close)
- Complete `PMSTATUSBUFFER` (`GwyStatus[16]`) and pointer-sized `HEV`/`HANDLE`
- Chunk writes at `MAX_MSGBUFFER_LEN` (4000); set `PM_ENDDOC` only on the final chunk
- Decode `PMDSTAT_*` status bits; query with `PM_NOTIFYIMMEDIATE` (not change-wait)
- Poll reads with `PM_NOWAIT` + timeout instead of indefinite blocking
- Add `XSPMGetConfiguredDevices`, `XSPMGetDeviceDescription`, `XSPMGetAltNodeName`,
  `XSPMNotifyApplicationState`, and `Devtypes.h` constants
- Add shared `CutePeripheral.flush()` (SITA → XSPMFlush; ARINC/RESA no-op)

## 0.1.0

- Initial ARINC TCP/RQB peripheral client
- Initial SITA `xspmapi.dll` FFI bindings (Windows)
- Initial RESA `crwnt_dm.dll` FFI bindings (Windows)
- Shared `CutePeripheral` API
