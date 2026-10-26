## 0.2.15

* Response classifier: print-steering prefixes (`CHKINERR3`, `TICKTERR6`, `BOARDERR2`, …) are hard errors.
  The previous `(^|[^A-Z0-9])ERR\d` boundary left those as `unknown` because a letter sat before `ERR`.
  EP params `ERR3IGN` / `ERR5PRT` are still stripped so `HDCEPOK#…` stays OK.

## 0.2.14

* **Fix power-cycle Access Denied:** ping/write paths that marked a serial session dead used to skip
  `SerialPort.close()` / `dispose()` on the next `close()` (`if (_closed) return`). Windows kept the COM
  handle in-process → ERROR_ACCESS_DENIED (5) on every reopen. Release is now always idempotent.
* Waiting while the COM port is **absent** no longer burns open-attempt budget; settle after reappear is
  ~2.5s; Access Denied backoff 3–15s; monitor keeps retrying after Access Denied (blockOnFailure: false).
* Discover no longer overwrites in-flight connecting/retrying with "discovering".

## 0.2.13

* Power-cycle reconnect: never open a synthetic COM name while the port is absent from the OS list (avoids
  ERROR_FILE_NOT_FOUND burning retries while the device is off).
* After a port **reappears**, settle ~1.5s before the first CreateFile; Access Denied (5) uses longer backoff +
  a short open cooldown so the monitor does not re-hammer the driver mid-init.
* Heartbeat / health recovery always settles before reopen; `reconnect` waits 800ms after close.

## 0.2.12

* Standalone power-cycle reconnect: monitor / heartbeat recovery no longer permanently blocks auto-connect after
  retries fail while the device is off (ghost COM still listed).
* Discover no longer synthesizes a COM match for a configured port that is **absent** from the OS list (that left
  powered-off printers stuck on "available"). Connect may still open by configured name as a last resort.
* Discover forgets stale ports when a match disappears; clears the auto-connect block only when a device
  **reappears**; does not overwrite connecting/retrying with "available".
* Explicit `connect(force: true)` cancels an in-flight retry loop, settles the COM handle, and rediscovers each
  attempt — UI Connect works after a stuck retrying/fail loop.
* `reconnect` uses `connect(force: true)`.

## 0.2.11

* Request-queue observability: `DcsQueueState` (`waiting` / `running` / `depth`), `DcsDeviceRequestQueue.state` /
  `states`, `DcsDeviceController.queueStateFor` / `queueStates` / `queueStatesFor`.
* `onStart` on `sendText` / `sendBytes` / `sendRequest` / `sendTextRequest` — runs when the command reaches the
  device (after everything queued before it), so apps can show queued → sending exactly.

## 0.2.10

* `DcsDeviceRequestOptions.postWriteHold` — optional hold after write/response before
  releasing the per-device queue (prefer waiting for real OK/error when the device replies).

## 0.2.9

* Per-device request queue supports `waitForResponse: false` (framed write still serialized on that COM).
* `connectAll` connects independent devices in parallel.
* Classifier: `isBusyError` helper; `BGRERR` treated as hard error; ERR3IGN-style params stay OK.

## 0.2.8

* Response classifier: do not treat `ERR3IGN` / similar EP param names as errors. `HDCEPOK` is OK; only `HDCERR` / token `ERR\d` fail.

## 0.2.7

* Serial writes re-assert RTS when enabled (matches standalone C# `SerialPortBase.Send`).

## 0.2.6

* AEA outbound framing restored for `auto` (and `framed`): wrap CP#/BTP/AV with STX/ETX. Export `dcsEncodeAeaOutbound` for fire-and-forget print writes.
* `none` stays raw.

## 0.2.5

* Exact COM port matching: configured `COM4` no longer binds to `COM44`/`COM40` via substring Pattern match.

## 0.2.4

* Serial writes loop with blocking timeout so large CP#/BTP payloads fully drain (non-blocking partial writes were aborting prints with no response log).
* Clearer Access Denied message when another app holds the COM port; refuse double-open of the same COM across profiles.

## 0.2.3

* `auto` protocol no longer wraps outbound STX/ETX (raw CP#/AV/BTP on the wire); only `framed` wraps. Fixes silent no-print after connect.

## 0.2.2

* Treat CUPPS `oc` as Passport Reader (OCR), same MRZ path as MSR (`ms`).
* Add LPT connection type + parallel adapter (LPT1–LPT3, accepts LTP typo) for document printer / DCP.

## 0.2.1

* Wrap outbound AEA commands in STX/ETX for `framed`/`auto` protocol modes.
* `auto` accepts either STX/ETX replies or quiet-window unframed text.
* Classify `PTOK`/`PROK` print acks as OK; harden ERR detection.
* Reconnect settles COM ports (delay + block monitor race) and backs off on Access Denied.

## 0.2.0

* CUPPS-aligned `DcsDeviceRole` catalog (bp/bt/bc/bg/ms/oc/pr/be/dd/zl/zi).
* Full serial options: DTR/RTS, protocol mode, thresholds, handshake aliases.
* Printer extras: printType, autoBin, logoBinary, resetBin.
* COM + LAN connection types; TCP network adapter.
* `textListenFor` reader stream helper; catalog seed + prefs merge.

## 0.1.0

* Initial release as part of the [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages) monorepo.
