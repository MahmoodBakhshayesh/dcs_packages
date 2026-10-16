import 'bp_codec.dart';
import 'bt_codec.dart';
import 'model.dart';
import 'template_codec.dart';
import 'tokenizer.dart';

/// Parse a PECTAB / template stream into a typed [PectabDocument].
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
      TemplateDocument() => TemplateDocument(
        header: doc.header,
        elements: [for (final e in doc.elements) TemplateCodec.parseElement(e.source)],
        trailing: doc.trailing,
        tableId: doc.tableId,
      ),
      RawDocument() => doc,
    };
  }
}
