import 'zebra_models.dart';

/// Heuristics for recognizing Zebra / ZDesigner printers in discovery lists.
class ZebraPrinterIdentity {
  const ZebraPrinterIdentity._();

  /// Windows Zebra driver stack commonly reports manufacturer as `ZDesigner`.
  static final _zebraManufacturer = RegExp(
    r'(zdesigner|zebra(\s*technologies)?)',
    caseSensitive: false,
  );

  static final _positive = RegExp(
    r'(zebra|zebra\s*technologies|zdesigner|\bzq\d|\bzd\d|\bzt\d|\bzr\d|\bql\d|'
    r'zq[0-9]{3}|zd[0-9]{3}|zt[0-9]{3}|ql[0-9]{2,3}|gc[0-9]{3}|gk[0-9]{3}|'
    r'gx[0-9]{3}|lp\s*2824|tlg\d|vid_0a5f)',
    caseSensitive: false,
  );

  static final _negative = RegExp(
    r'(buds|airpods|headset|headphone|earbud|speaker|watch|phone|mouse|keyboard|'
    r'gamepad|controller|tv|audio|beats|galaxy\s*buds|pixel\s*buds)',
    caseSensitive: false,
  );

  static final _genericManufacturer = RegExp(
    r'^(microsoft(\s+corporation)?|\(standard\b.*|standard\s+system\s+devices)$',
    caseSensitive: false,
  );

  static bool isZebraManufacturer(String? manufacturer) {
    final value = manufacturer?.trim() ?? '';
    if (value.isEmpty) return false;
    return _zebraManufacturer.hasMatch(value);
  }

  /// Driver-stack fillers (e.g. Microsoft BTHENUM COM ports) are not device OEMs.
  static bool isKnownManufacturer(String? manufacturer) {
    final value = manufacturer?.trim() ?? '';
    if (value.isEmpty) return false;
    return !_genericManufacturer.hasMatch(value);
  }

  static bool looksLikeZebra(ZebraPrinterDescriptor descriptor) {
    final manufacturer = descriptor.manufacturer?.trim() ?? '';
    // When a real OEM manufacturer is known, only keep ZDesigner / Zebra.
    if (isKnownManufacturer(manufacturer)) {
      return isZebraManufacturer(manufacturer);
    }

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
