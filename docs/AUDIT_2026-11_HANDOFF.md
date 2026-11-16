# dcs-packages — system audit handoff (2026-11-16)

For: developers and agents working in `dcs-packages`.
Companions: Flutter `dcs/docs/audit-2026-11/FLUTTER_HANDOFF.md`, backend
`dcs-api/docs/audit-2026-11/BACKEND_HANDOFF.md`.

Branch: `fix/system-audit-2026-11` (cut from `main` at `12c2aae`, **nothing committed, nothing pushed**).

Important: the app (`dcs/pubspec.yaml`) takes seven packages from `ref: main`. **Anything merged to `main` reaches the
app on the next `pub upgrade`.** Review this branch before merging; bump versions + CHANGELOG when you do.

Severity: **C** critical · **H** high · **M** medium · **L** low. **FIXED** = changed in this branch; the rest is
OPEN. "Unverified" = read from code, not confirmed on hardware. Paths are under `packages/`.

Not reviewed in depth: Zebra native plugin code, `dcs_status_widgets.dart`, `cupps_configure.dart`,
`cupps_status_assets.dart`, the first ~225 lines of `cupps_device.dart`, `sita_ffi.dart` struct layouts, PECTAB
geometry / catalog / lint / model files. No real device was used.

## 0. Verification of this branch

| Package | Tests after the change |
| --- | --- |
| `dcs_cupps` | 25 pass (1 new) |
| `dcs_zebra` | 28 pass (2 new) |
| `dcs_mrz` | 4 pass (2 new) |
| `dcs_cute` | 5 pass (1 new) |

`dcs_cute` tests could only be run by temporarily pointing its local `pubspec_overrides.yaml` at `../dcs_common`: the
git-ignored, melos-generated file on this machine contains a Windows path (`..\\dcs_common`). The file was restored.
On this Flutter master, `flutter test` also rewrites `analysis_options.yaml` (adds `analyzer.exclude`) — reverted, not
part of the branch.

## 1. Changes made

| # | Sev | File | What was wrong | Change |
| --- | --- | --- | --- | --- |
| PF1 | C | `dcs_cupps/lib/src/cupps_framing.dart`, `cupps_client.dart` (`_onBytes`) | One frame with a non-UTF-8 byte (e.g. Latin-1 `0xE9` in a name) made `utf8.decode` throw **before** the frame was removed from the buffer, and `_decoder.add` sat outside the `try` → unhandled zone error, the bad frame stayed at the head, every later chunk re-threw → the socket session was dead until reconnect. | Frame removed before decoding; `allowMalformed: true` (bad bytes become U+FFFD); `_decoder.add` wrapped + logged. Test added. |
| PF2 | H | `dcs_cute/lib/src/cute_matip_codec.dart` (`_drain`) | Same poison-frame pattern: an unknown control command (e.g. `01 FB 00 04`) threw before the buffer advanced → the session never received another packet. | Frame removed first; an undecodable packet is skipped. Test added. |
| PF3 | M | `dcs_zebra/lib/src/zebra_status_parser.dart` | `~HS` string 1 is `aaa,b,c,dddd,eee,f,…`: index 4 (`eee`) is the **number of formats in the receive buffer**, index 5 (`f`) is the buffer-full flag. The parser read index 4 → two queued labels reported `bufferFull` → state `degraded` → `printBatch(waitForReady: true)` stalled between jobs. | `bufferFull = _flag(first, 5)`. Two tests added. |
| PF4 | H | `dcs_mrz/lib/dcs_mrz.dart` | TD3: when the optional-data field is all `<`, ICAO 9303-4 allows its check digit to be `<` or `0`. The parser required the computed `0` → valid passports reported `valid == false`; the app's camera consensus requires `.valid`, so those passports never scanned. | `<` accepted only when the personal number is all filler. Two tests added (accept + still reject when data is present). |
| PF5 | M | `dcs_cupps/lib/src/cupps_device.dart` (`aeaRequest`) | With `waitForDeviceAck: true` and a non-OK outbound result, the method returned without `cancelInboundAeaWait` → the stale wait swallowed later unsolicited reader data (gate scans without "OK" / "ERR" silently dropped). | The wait is cancelled on the non-OK path. |

## 2. Version and ref drift (app vs this repo)

| Package | App ref | State |
| --- | --- | --- |
| `dcs_device_util` | SHA `12c2aae` (0.2.15) | OK. No `dcs_device_util-v*` tag exists. |
| `dcs_zebra` | SHA `82b9ca8` (0.2.1) | Tag `dcs_zebra-v0.2.1` (`ecc7cc4`) points at a commit whose pubspec still says 0.2.0; the bump and the iOS `LIBRARY_SEARCH_PATHS` fix come after the tag and the fix has no CHANGELOG entry. |
| `dcs_pectab` | tag `dcs_pectab-v0.1.5` | OK. 0.1.4 is in the CHANGELOG but untagged. |
| `dcs_common`, `dcs_cupps`, `dcs_cute`, `dcs_cute_peripherals`, `dcs_documents`, `dcs_bcbp`, `dcs_mrz` | `ref: main` | **Floating.** |
| `dcs_baggage`, `dcs_host`, `dcs_simulator`, `dcs_certification` | only under `dependency_overrides:` | See P28. |

- Every package depends on `dcs_common` via `git ref: main`, so pinning zebra or device_util by SHA still floats
  `dcs_common`.
- `dcs_common` is `1.0.0` with an "Unreleased" CHANGELOG section that `dcs_zebra` needs; tag `v1.0.0` does not contain it.
- `dcs_cupps` CHANGELOG skips 0.1.4.
- The app imports only public barrels (no `package:dcs_*/src/...`).

Recommendation: tag every release, pin the app to tags, and pin `dcs_common` inside the packages.

## 3. Open — sockets, framing, queues

| # | Sev | Where | Problem | Fix (API-compatible) |
| --- | --- | --- | --- | --- |
| P2b | H | `dcs_cute/lib/src/cute_client.dart:153-167,194-201`, `cute_models.dart:89-92` | `_handlePacket` throws on a data packet shorter than the id length — drops the rest of the batch and escapes the listener. | Wrap `_onBytes`; catch per packet. |
| P3 | H | `dcs_cupps/lib/src/cupps_transport.dart:44-54`, `cupps_client.dart:1841-1863` | Sockets are never destroyed on error or remote close: on FIN `_socket` is nulled without `destroy()` (handle leak per drop); on error `_socket` stays non-null so `isOpen` is true and later requests each wait the full 12 s timeout. `dcs_cute/lib/src/cute_transport.dart` is a drifted copy. (FD lifetime unverified at runtime.) | In both callbacks take the socket, null the field, `destroy()`; in the session's `_onError` / `_onDone` call `close(notify: true)`. |
| P4 | H | `cupps_client.dart:1559-1599` | After the platform socket drops, state flips `disconnected` → `degraded` up to 45 s later (heartbeat throws), timers keep running, device sockets stay open. The app renders `degraded` as "In use". `autoReconnect` only gates the heartbeat — no reconnect exists. | Cancel both timers and close device sessions in `_handlePlatformClosed`; skip the degraded overwrite when the session is closed. |
| P5 | H | `cupps_client.dart:77-105, 107-191, 200-202` | connect / authenticate / connectDevices never emit `failed` (the enum value is never set); one bad device aborts the whole bring-up (`Future.wait`) and the platform sticks at `discoveringDevices`. | Catch per device; set `CuppsPlatformState.failed` and rethrow in the three public methods. |
| P6 | M | `dcs_cupps/lib/src/cupps_device.dart:785-791` | `print`'s `finally` overwrites `failed` / `disconnected` with `initialized` → a healthy-looking device with no session. | Only clear `printing`; keep the state unless still `busy`. |
| P7 | M | `cupps_device.dart:718-719,774-781` | Print reports `ok: true` when the printer ack is merely late (> 8 s, intentional per CHANGELOG 0.1.5); a late `PRERR` / `HDCERR` is logged as "unmatched". | Keep the default but return a distinct `result: 'acceptedNoAck'`; surface a late `ERR` through device status. |
| P9 | M | `cupps_client.dart:838,1637,1046,921` | Disconnect / dispose races: an in-flight `_connectDevice` stores a live session after `disconnect()` cleared the map (orphan socket) or adds to a closed controller (`StateError`). | `_disposed` / epoch check after each await; `isClosed` guards. |
| P10 | M | `dcs_cute/lib/src/cute_client.dart:57-64, 94-100, 131-144`; `cute_models.dart:311` | Second `connect()` overwrites transport / subscription without closing; `_decoder.reset()` never called; a failed open leaves the socket open; `close()` throws on a dead socket; `closeTimeout` unused. | Teardown + reset at the start of `connect()`; try/catch → `failed`; `close()` with try/finally + timeout. |
| P11 | H | `dcs_device_util/lib/src/dcs_request_queue.dart:246-307, 370-409` | Standalone request queue: (a) the timeout does not cover `write` — an offline LPT / stalled LAN flush blocks the whole device queue forever; (b) command A times out, its `PROK` arrives during B → B classified OK from A's reply; (c) the frame parser returns at the first ETX and drops a second frame in the same read; (d) `onError: completer.completeError` can throw on a second error; (e) stream done not handled. | `write(...).timeout(options.timeout)`; `isCompleted` guard; `onDone`; drain one quiet window after a timeout; keep leftover bytes. |
| P12 | H | `dcs_device_util/lib/src/dcs_adapters.dart:248, 293-304`; `dcs_cute_peripherals/lib/src/sita/sita_device.dart:84-134,226,298`; `resa/resa_device.dart:170-177` | Blocking sync IO on the UI isolate: serial `_port.write(chunk, timeout)` up to 8 s (printer holding CTS / XOFF freezes the UI); `SerialPort.availablePorts` on every write and every 3 s heartbeat; SITA `XSPM*` with `pmWait` (lock up to 120 s); RESA `CRW_DM_READ`. | ≤ 256-byte chunks with a short per-chunk timeout and a yield between chunks; cache `availablePorts` ~2 s; SITA / RESA behind `Isolate.run` or `PM_NOWAIT` polling. |
| P13 | M–H | `dcs_adapters.dart:346-408` | LAN printer session never notices a remote close (`isOpen => !_closed`, `onDone` does not set `_closed`) → first print after a power cycle times out; `close()` awaits `_socket.close()` and can hang. | `_closed = true` in `onDone` / `onError`; `destroy()`. |
| P14 | M | `dcs_cute_peripherals/lib/src/arinc/arinc_device.dart:60-83, 173-186, 243-247, 272-285` | ARINC: cannot reconnect after an error without an explicit `close()`; orphaned ack completers; ack + data reply in one TCP read loses the reply; `ack.commandStatus` never checked (unverified vs PCP32). | Register completers in try/catch; serialise sends; buffer undelivered inbound bodies; close on error. |
| P15 | M | `dcs_zebra/lib/src/transport/tcp_zebra_transport.dart:123-144`, `zebra_printer.dart:253-259, 289-299` | `~HS` returns three STX / ETX strings; the first poll returns whatever arrived (head-open / ribbon-out read as false); no command serialisation → a status poll interleaved with `getDarkness()` swaps the replies; `disconnect()` can hang. | Read until three ETX or timeout; per-printer async mutex; `destroy()`. |
| P16 | M | `zebra_printer.dart:418, 501, 163, 629-634` | `printBatch` → `unawaited(_runBatch(...))`; a disconnect makes `printRaw` throw → unhandled error and the controller is never closed → the caller's `await for` never ends (the app's `TouchPrintBatchRunner` awaits it — Flutter O23). | try/catch/finally in `_runBatch` that emits `failed` and always closes; `printRaw` returns `ok: false, result: 'notConnected'`. |
| P17 | L–M | `dcs_device_util/lib/src/dcs_device_controller.dart:158-222, 273-285, 494-532, 624-655`; `dcs_models.dart:427, 638-641` | Unawaited `connect()` can throw after `dispose()`; `discover()` overwrites `failed` (message disappears); `connect(force: true)` silently returns after 5 s; `textListenFor` leaks its subscription and frames purely by a 40 ms quiet window (split / merged barcodes), decodes Latin-1 while the doc says ASCII / UTF-8; a corrupt stored config makes `start()` throw. | `.ignore()`; skip `failed` in `discover()`; try/catch in `load()`; subscribe in `onListen`. |

## 4. Open — parsers

| # | Sev | Where | Problem | Fix |
| --- | --- | --- | --- | --- |
| P18 | H | `dcs_bcbp/lib/dcs_bcbp.dart:82-90`; app `dcs/lib/features/boarding/domain/boarding_scan_identifier.dart:144-146` | BCBP: only the **first leg** is parsed (`legs: [_parseLeg(firstLeg)]` while `numberOfLegs` may be 2–4); the app compares `data.legs.first` → an `M2…` pass is rejected "Wrong flight" at the second leg's gate. Missing: conditional-section size, later legs, PNR, passenger status, Julian date → date, security data. `raw.length < 60` rejects scans with stripped trailing spaces; no AIM `]` prefix strip; the test fixture is not a valid BCBP. | Additive: loop over `numberOfLegs`, read the 2-hex variable size after each 37-char block, bounds-checked; optional `pnr` / `passengerStatus`. App: match any leg. Needs real M2 fixtures before release. |
| P19b | M | `dcs_mrz/lib/dcs_mrz.dart` | Still missing after PF4: composite check digit (`second[43]`), TD1 / TD2 (the app partially re-implements them in `mrz_frame_consensus.dart:51-60`), name-truncation flag, date century inference; `checkDigit` throws on any OCR char outside `[0-9A-Z<]`. | Add the composite check and `MrzTd1Document` / `MrzTd2Document`. |
| P21 | M | `dcs_baggage/lib/dcs_baggage.dart:17-19` | 9-digit tag model, no 10-digit licence-plate parser, no BSM parser (README says "BSM-style"). | `BaggageTag.tryParse` accepting 9 or 10 digits + optional `leadingDigit`. |
| P22 | L | `dcs_request_queue.dart:76`, `cupps_client.dart:1487,1514`, `dcs_pectab/lib/src/aea_answer.dart:39` | AEA replies classified by loose substring (`contains('OK')`, `contains('ERROR')`, `ERR[0-9A-Z]` matches `ERROR`). | Anchor on tokens. |
| P23 | L | `cupps_framing.dart:78`; `cupps_client.dart:1613-1617, 1820`; `cupps_xml.dart:226-244, 561-619` | Frame length accepts a signed hex (negative → `RangeError`), no max payload cap; empty `result` counts as OK; `_pending.remove` does not check for a `*Response`; `decodeBcDataPayload` base64-decodes any text that happens to be valid base64 (barcode `QUJD` → `ABC`) and the app calls it twice; `messageLogData` re-parses the XML ~4× per call. | `^[0-9A-Fa-f]{6}$` + cap; stricter checks. |

PECTAB tokenizer and codecs are defensive — no unchecked `substring` found. One trap: rotation letters differ between
the two barcode forms (`bp_codec.dart:110-115` R=180 / L=90 vs `:192-196` R=90 / L=270), documented only in a comment.

## 5. Open — robustness, platform, consistency

| # | Sev | What | Fix |
| --- | --- | --- | --- |
| P24 | M | Web target (unverified, not built): the app imports `dcs_cute_peripherals` (`dart:ffi`) and `dcs_device_util` (`flutter_libserialport`) unconditionally; `dcs_common` imports `dart:io` at library level, so the pure-Dart contract packages inherit it. | Conditional exports with stubs; split `DcsStandardLogStore` into an IO library. |
| P25 | L–M | Missing platform guards: `DcsDeviceController` defaults to Serial + Network + LPT on every platform (LPT1–3 offered on macOS / Android; libserialport lookup fails every 5 s on iOS). Error contracts differ: `UnsupportedError` from SITA / RESA `load()`, sync `ArgumentError` + raw `TimeoutException` from `DcsHostClient.send`, `PlatformException` from the Zebra method channel, `ArgumentError` on non-ASCII from `CuteClient.sendText`. | Per-platform adapter defaults; wrap in the package's own failure types. |
| P26 | M | Encoding: `DcsDeviceRequestOptions.encoding` defaults to `utf8` and the app never overrides it → `MÜLLER` goes to a serial ATB / BTP printer as multi-byte UTF-8 (garbled, shifts fixed-width fields); `AeaHelpers.asciiBytes` is `utf8.encode` while `decodeAscii` is Latin-1; `ZebraPrinter.printRaw` always UTF-8. | Default `latin1` for AEA (or per-profile) + sanitise; rename / alias the helper. |
| P27 | L | Logging: `jsonEncode` on arbitrary `data` can throw; sync `jsonEncode` per event; `existsSync()` per log line; no rotation / size cap. | Guard, buffer, rotate. |
| P28 | M | App `dcs/pubspec.yaml:122-153`: the `dependency_overrides:` header is followed by live git entries for `dcs_mrz` (duplicate), `dcs_baggage`, `dcs_host`, `dcs_simulator`, `dcs_certification`. `dcs_baggage` and `dcs_certification` are imported by the app but are not in `dependencies`; `dcs_host` and `dcs_simulator` are not imported at all. It looks like the header swallowed the tail of the dependency list. | Move the entries under `dependencies`; delete the override block. **Not changed** — it alters dependency resolution; do it with a full build on every platform. |
| P29 | L | Duplication / drift: six endpoint classes, seven state enums bridged only by the app, `DcsDeviceKind` defined twice with different values, seven unrelated exception types, three ~200-line logger copies + a fourth shape, `cupps_transport.dart` / `cute_transport.dart` copies, `DcsPackageModule` lacks `pectab` / `cutePeripherals`. | Converge on `dcs_common` types over time. |

## 6. Tests, analyzer, CI

| Package | lib LOC | tests (before) | Gap |
| --- | --- | --- | --- |
| `dcs_bcbp` | 109 | 2 | No multi-leg / conditional tests; invalid fixture |
| `dcs_mrz` | 93 | 2 | No composite, TD1, TD2 |
| `dcs_cute` | 1346 | 4 | No reconnect, close-on-dead-socket, timeout |
| `dcs_cute_peripherals` | 2027 | 4 | Only the RQB codec |
| `dcs_cupps` | 4720 | 24 | No socket error / close, disconnect races, print state |
| `dcs_device_util` | 3543 | 29 | No stale-response, write-hang, coalesced-frame; LAN / LPT untested |
| `dcs_zebra` | 2415 | 26 | No partial `~HS`, no batch-disconnect |
| `dcs_pectab` | 2342 | 78 | Good |
| others | 47–408 | 1–3 | Smoke only |

- No root `analysis_options.yaml`; `unawaited_futures`, `discarded_futures`, `cancel_subscriptions`, `close_sinks` are
  not enabled — several findings above would be flagged by them.
- No CI (`.github` absent); melos `test` / `analyze` scripts exist but nothing runs them.
- There are no `TODO` / `UnimplementedError` markers — the gaps are silent: `dcs_documents` `toPayload()` emits plain
  text, not AEA / PECTAB; `dcs_host` is an interface + pass-through; `dcs_simulator` has no CUPPS / serial / Zebra
  simulators; `dcs_certification` has one check; `ArincDevice.flush()` / `ResaDevice.flush()` are no-ops;
  `characterSet` is sent in CUTE Session Open but never applied to payload encoding.

## 7. Suggested order

1. Review + merge this branch with version bumps and CHANGELOG lines (`dcs_cupps`, `dcs_cute`, `dcs_zebra`, `dcs_mrz`).
2. P3 / P4 / P5 (CUPPS socket lifecycle and `failed` state), P11 a/d/e (queue write timeout), P13, P16.
3. P18 multi-leg BCBP (+ one-line app change) with real fixtures.
4. P12 (blocking IO) and P26 (encoding) — test on real printers.
5. P28 app pubspec, tags, pin `dcs_common`.
6. Root analyzer options with the four async lints; a CI job running `melos run analyze` + tests.
