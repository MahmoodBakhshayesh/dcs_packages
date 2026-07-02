# dcs_cute

CUTE/MATIP socket utilities and certification rule helpers for Flutter DCS
applications.

## Install (git)

```yaml
dependencies:
  dcs_cute:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_cute
      ref: main
```

The public common-use documentation points to two different layers:

- CUPPS/ITPS for common-use peripheral/device exchanges such as ATB, BTP, BGR,
  SBD, and scale devices.
- MATIP (RFC 2351) for mapping airline reservation, ticketing, and messaging
  traffic over TCP/IP.

This package focuses on the second layer: opening a MATIP-style socket session,
encoding/decoding packets, sending DCS payloads, collecting structured logs, and
running local pre-certification configuration checks. Device-specific CUPPS/ITPS
XML and AEA peripheral handling should live in `dcs_cupps`.

## Features

- MATIP packet codec for `Session Open`, `Open Confirm`, `Session Close`, and
  data packets.
- Fragmented/batched socket stream decoder.
- Configurable Type A conversational, Type A host-to-host, and Type B profiles.
- TCP client with session-open handshake, inbound message stream, and clean
  close handling.
- Injectable transport for simulators, vendor certification harnesses, and
  tests.
- Structured lifecycle/socket/MATIP logs with optional JSONL file sink.
- CUTE pre-certification rule helper for common configuration mistakes.

## Getting started

Add this package to the Flutter DCS application and create a `CuteClient`. The
package does not include airport/vendor credentials, paid IATA specification
content, or platform-specific test scripts. Confirm exact values such as host,
port, ASCU/HLD addressing, character set, and payload format with the airport
platform provider or certification lab.

## Usage

```dart
final config = CuteSessionConfig(
  trafficType: CuteTrafficType.typeA,
  subtype: CuteTrafficSubtype.conversational,
  characterSet: CuteCharacterSet.ascii7Bit,
  multiplexMode: CuteMultiplexMode.singleAscu,
  addressHeader: CuteAddressHeader.none,
  presentation: CutePresentation.p1024b,
);

final endpoint = const CuteEndpoint(host: '127.0.0.1', port: 350);

final findings = const CuteCertificationRules().evaluate(
  CuteCertificationProfile(endpoint: endpoint, session: config),
);
if (findings.any((finding) => finding.isBlocking)) {
  throw StateError('CUTE/MATIP profile is not ready for certification.');
}

final client = CuteClient(
  logger: CuteLogger(
    sinks: [
      CuteFileLogSink(directory: Directory('C:/DCS/cute_logs')),
    ],
  ),
);

client.status.listen((status) {
  debugPrint('${status.state.name}: ${status.message}');
});

client.messages.listen((message) {
  debugPrint('Host payload: ${message.text}');
});

await client.connect(endpoint: endpoint, config: config);
await client.sendText('DCS HOST MESSAGE');
await client.close();
```

## Additional information

Useful public references:

- IATA Common Use standards describe the CUPPS/CUTE/CUSS common-use context.
- IATA ITPS describes DCS-to-device peripheral exchanges; the full technical
  specification is controlled by IATA.
- RFC 2351 describes MATIP packet/session mapping over TCP/IP.

Certification still depends on the target platform. Treat this package as a
general socket/protocol foundation and keep airport-specific rules in app-level
configuration and simulator-backed tests.
