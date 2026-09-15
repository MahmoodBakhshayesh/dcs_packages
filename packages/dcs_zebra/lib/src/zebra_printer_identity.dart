import 'zebra_models.dart';

/// Heuristics for recognizing Zebra Link-OS / mobile printers in discovery lists.
class ZebraPrinterIdentity {
  const ZebraPrinterIdentity._();

  static final _positive = RegExp(
    r'(zebra|zebra\s*technologies|\bzq\d|\bzd\d|\bzt\d|\bzr\d|\bql\d|\bi\w?mz\b|'
    r'zq[0-9]{3}|zd[0-9]{3}|zt[0-9]{3}|ql[0-9]{2,3}|gc[0-9]{3}|gk[0-9]{3}|'
    r'gx[0-9]{3}|lp\s*2824|tlg\d|printer)',
    caseSensitive: false,
  );

  static final _negative = RegExp(
    r'(buds|airpods|headset|headphone|earbud|speaker|watch|phone|mouse|keyboard|'
    r'gamepad|controller|tv|audio|beats|galaxy\s*buds|pixel\s*buds)',
    caseSensitive: false,
  );

  static bool looksLikeZebra(ZebraPrinterDescriptor descriptor) {
    final haystack = [
      descriptor.name,
      descriptor.model,
      descriptor.address,
      descriptor.id,
    ].whereType<String>().join(' ');
    return looksLikeZebraText(haystack);
  }

  static bool looksLikeZebraText(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    if (_negative.hasMatch(value)) return false;
    return _positive.hasMatch(value);
  }

  static List<ZebraPrinterDescriptor> onlyZebra(
    Iterable<ZebraPrinterDescriptor> devices,
  ) {
    return devices.where(looksLikeZebra).toList(growable: false);
  }
}
