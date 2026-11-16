
# dcs-packages robustness

Open findings: `docs/AUDIT_2026-11_HANDOFF.md`. Consumer: the DCS app (`../dcs`), which takes several packages from
`ref: main` — **what lands on `main` ships**.

## Stream decoders (CUPPS, MATIP, AEA, Zebra)

- Remove a frame from the buffer **before** decoding it. A frame that cannot be decoded is logged and skipped; it must
  never stay at the head of the buffer.
- Nothing may throw out of a socket / serial `listen` callback. Wrap the whole callback.
- Never assume one read = one message: handle split and coalesced frames, keep leftover bytes.
- Decode bytes from devices leniently (`allowMalformed` / Latin-1); cap declared lengths; reject negative lengths.

## Sockets, sessions, queues

- On error or remote close: take the socket, null the field, `destroy()` it, cancel timers, fail pending completers,
  and set a terminal state (`failed` / `disconnected`) — never leave `isOpen` true on a dead socket.
- Every `Completer` has a timeout and an `isCompleted` guard; a timeout must also cover the **write**.
- A registered wait (ack, reply) is always cancelled on every exit path (`finally`).
- After each `await` in connect / reconnect paths, re-check disposed / epoch before storing state or adding to a
  controller.
- No blocking sync IO on the UI isolate (serial write with a long timeout, FFI calls that wait): chunk + yield, or run
  in an isolate.
- A `finally` must not overwrite a failure state with a healthy one.

## Parsers (BCBP, MRZ, bag tag, PECTAB)

- No unchecked `substring` on device input — bounds-check and throw the package's parse exception.
- Follow the standard's optional forms (e.g. `<` as the check digit of an empty MRZ optional field; BCBP conditional
  sections and multiple legs). Every rule gets a test with a real-format fixture.
- Document field indexes next to the format string they come from (`~HS`: `aaa,b,c,dddd,eee,f,…`).

## Public API and releases

- Keep the public API compatible: add optional named parameters / new classes; do not change meanings.
- Throw the package's own failure types across the public API, not `StateError` / `PlatformException` /
  `TimeoutException`.
- A behaviour fix ships with a test, a version bump and a CHANGELOG line; tag the release and keep the tag on the
  commit that has the bumped pubspec.
- Guard platform-specific code (COM / LPT / FFI) so it does not run or fail in a loop on other platforms.

## Tool noise

`flutter test` on the current Flutter master rewrites `analysis_options.yaml` (adds `analyzer.exclude`). Do not commit
that. `pubspec_overrides.yaml` is melos-generated and git-ignored; a Windows path in it breaks tests on macOS / Linux —
regenerate with `melos bootstrap`.
