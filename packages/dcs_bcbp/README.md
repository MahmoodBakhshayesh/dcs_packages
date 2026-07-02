# dcs_bcbp

IATA **BCBP** (bar-coded boarding pass) parsing for DCS check-in and boarding flows.

## Features

- Parse mandatory multi-leg format (`M1…`)
- Extract passenger name, origin, destination, seat, sequence, and flight fields
- `BcbpParseException` for invalid payloads

## Install (git)

```yaml
dependencies:
  dcs_bcbp:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_bcbp
      ref: main
```

## Usage

```dart
import 'package:dcs_bcbp/dcs_bcbp.dart';

final data = BcbpData.parse(
  'M1DOE/JOHN            EABC1234IKADXB123Y012A0001'.padRight(60),
);

print(data.passengerName.surname); // DOE
print(data.legs.single.origin);    // IKA
print(data.legs.single.seat);      // 012A
```

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages).
