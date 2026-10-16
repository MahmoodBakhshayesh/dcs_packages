/// Lossless AEA PECTAB codec (boarding pass + bag tag).
///
/// Format: DCS `design/pectab-builder/SPEC.md`. Round-trip guarantee and model:
/// `ARCHITECTURE.md`. Implementation lands in tickets P2–P10.
library;

/// Package version string (matches [pubspec] `version` major.minor for tags).
const String dcsPectabVersion = '0.1.0-dev';
