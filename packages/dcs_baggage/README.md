# dcs_baggage

Baggage tag and baggage service message domain models for DCS applications.

## Features

- `BaggageTag` with airline numeric code and serial validation
- `CheckedBag` with destination, weight, and rush flag
- `BaggageServiceMessage` (BSM-style) completeness checks

## Install (git)

```yaml
dependencies:
  dcs_baggage:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_baggage
      ref: main
```

## Usage

```dart
import 'package:dcs_baggage/dcs_baggage.dart';

const tag = BaggageTag(airlineNumericCode: '123', serialNumber: '456789');
const bag = CheckedBag(tag: tag, destination: 'DXB', weightKg: 23.5);

final message = BaggageServiceMessage(
  type: BaggageMessageType.bsm,
  flightNumber: 'AB123',
  origin: 'IKA',
  bags: [bag],
);
print(message.isComplete); // true
```

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages).
