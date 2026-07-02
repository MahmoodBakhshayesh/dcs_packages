# dcs_documents

Boarding pass, bag tag, and generic AEA document payload builders for DCS printers.

## Features

- `DcsDocumentPayload` with device kind and stock metadata
- `BoardingPassDocument` and `BagTagDocument` helpers that produce printable content
- Integration with `DcsDeviceKind` from `dcs_common`

## Install (git)

```yaml
dependencies:
  dcs_documents:
    git:
      url: https://github.com/MahmoodBakhshayesh/dcs_packages.git
      path: packages/dcs_documents
      ref: main
```

## Usage

```dart
import 'package:dcs_documents/dcs_documents.dart';

final payload = const BoardingPassDocument(
  passengerName: 'DOE/JOHN',
  flightNumber: 'AB123',
  origin: 'IKA',
  destination: 'DXB',
  seat: '12A',
  sequenceNumber: '001',
).toPayload(documentId: 'bp-001');

print(payload.content);
```

## More information

Part of [dcs_packages](https://github.com/MahmoodBakhshayesh/dcs_packages).
