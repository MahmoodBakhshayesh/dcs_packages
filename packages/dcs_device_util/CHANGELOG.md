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
