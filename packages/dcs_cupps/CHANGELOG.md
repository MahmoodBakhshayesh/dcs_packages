## 0.1.6

* Treat acquire/status `powerOff` / offline as disconnected — do not mark acquired or auto-restart (stops BG init loops).
* Cap session-fault auto-restarts (`maxSessionFaultRestarts`, default 2).
* `CuppsHardwareStatus` helpers; UI maps `degraded` → **In use** / **Locked by others**.

## 0.1.5

* Print AEA ack accepts `PTOK` (HDC) as well as `PROK`; longer print ack wait; tolerate missing ack when outbound OK.
* Reader visual status: locked + ready shows active.

## 0.1.3

* **Configure / print as one status period** — while `configuring` or `printing` is set, intermediate `sendDeviceRequest` successes no longer flip the device to `initialized` (avoids busy↔initialized flicker during multi-command init).
* **`completeConfigure`** — keeps `configuring: true` for the whole command list and only clears it on the final success/failure status.

## 0.1.2

* Align `aeaRequest` with cupps-01.03 (`aeaMessage` / `aeaText`).
* Align `printRequest` with cupps-01.03 (`printDocument` / `simpleTextPrintDocument`).
* Fix `byeRequest` element/messageName (`bye` → `byeRequest`).
* Bundle `schema/cupps-01.03.0017.xsd` for reference.

## 0.1.1

* Package maintenance release.

## 0.1.0

* Initial release as part of the [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages) monorepo.
