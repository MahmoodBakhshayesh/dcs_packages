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
      BtDocument d => BtDocument(
        header: d.header,
        elements: [for (final e in d.elements) BtCodec.parseElement(e.source)],
        trailing: d.trailing,
        version: d.version,
        kind: d.kind,
        continuationChar: d.continuationChar,
        autoIncrement: d.autoIncrement,
        colorChar: d.colorChar,
        tagWidth10: d.tagWidth10,
        mirrorPointMm: d.mirrorPointMm,
        elemRefChar: d.elemRefChar,
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
