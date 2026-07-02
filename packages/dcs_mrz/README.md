# dcs_mrz

Passport **MRZ** (TD3) parsing and check-digit validation for DCS passenger identification.

## Features

- Parse two 44-character TD3 lines
- Extract document number, names, nationality, dates, and sex
- Validate check digits for document number, birth date, expiry, and personal number

## Install (git)

```yaml
dependencies:
  dcs_mrz:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_mrz
      ref: main
```

## Usage

```dart
import 'package:dcs_mrz/dcs_mrz.dart';

final doc = MrzTd3Document.parse(line1, line2);
print('${doc.primaryIdentifier} ${doc.secondaryIdentifier}');
print('Valid: ${doc.valid}');
```

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages).
