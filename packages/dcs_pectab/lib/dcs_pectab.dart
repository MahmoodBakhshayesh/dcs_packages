/// Lossless AEA PECTAB codec (boarding pass + bag tag).
///
/// Format: DCS `design/pectab-builder/SPEC.md`. Round-trip guarantee and model:
/// `ARCHITECTURE.md`.
library;

export 'src/bp_codec.dart';
export 'src/bt_codec.dart';
export 'src/template_codec.dart';
export 'src/model.dart';
export 'src/parse.dart';
export 'src/tokenizer.dart';

/// Package version string (matches [pubspec] `version`).
const String dcsPectabVersion = '0.1.0-dev';
