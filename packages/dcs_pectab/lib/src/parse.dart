import 'bp_codec.dart';
import 'bt_codec.dart';
import 'model.dart';
import 'tokenizer.dart';

/// Parse a PECTAB / template stream into a typed [PectabDocument].
///
/// Tokenizes first (verbatim sources), then classifies body elements with the
/// available codecs. Unknown bytes stay [UnknownElement].
abstract final class Pectab {
  static PectabDocument parse(String input) {
    final doc = PectabTokenizer.tokenize(input);
    return switch (doc) {
      BpDocument() => BpDocument(
        header: doc.header,
        elements: [for (final e in doc.elements) BpCodec.parseElement(e.source)],
        trailing: doc.trailing,
        tableId: doc.tableId,
        emd: doc.emd,
      ),
      BtDocument() => BtDocument(
        header: doc.header,
        elements: [for (final e in doc.elements) BtCodec.parseElement(e.source)],
        trailing: doc.trailing,
        version: doc.version,
        kind: doc.kind,
      ),
      TemplateDocument() => doc, // BOX/LINE: P5
      RawDocument() => doc,
    };
  }
}
