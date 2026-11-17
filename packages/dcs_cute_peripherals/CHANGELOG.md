## 0.2.1

- SITA and RESA FFI calls no longer run on the caller's (UI) isolate. Each `SitaDevice` / `ResaDevice` owns a
  `CuteFfiWorker` isolate; `XSPMOpen` / `XSPMLock` / `XSPMWrite` (`PM_WAIT`) and `CRW_DM_LOCK` / `CRW_DM_READ` used to
  freeze the app for up to their wait (lock 10 s, RESA read 5 s, SITA open indefinitely). Same public API, same call
  order (one call at a time per device), same timeouts and error types.
- `close()` waits at most 5 s for the worker, so `dispose()` can no longer hang behind a stuck native call; the worker
  isolate is killed on `dispose()`.
- Caveat: Dart does not pin an isolate to one OS thread. Not yet run on a CUTE workstation.

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
