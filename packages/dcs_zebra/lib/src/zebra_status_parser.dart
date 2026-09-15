import 'dart:convert';
import 'dart:typed_data';

import 'zebra_models.dart';

/// Parses Zebra host status (`~HS`) and Link-OS-style status maps into
/// [ZebraPrinterStatus] flags.
class ZebraStatusParser {
  const ZebraStatusParser._();

  /// `~HS` returns three comma-separated lines. Flag bits follow the classic
  /// ZPL host-status layout used by Link-OS network printers.
  static ZebraPrinterStatus fromHostStatus(
    String raw, {
    required ZebraPrinterDescriptor printer,
    ZebraPrinterStatus? previous,
  }) {
    final base = previous ?? ZebraPrinterStatus.discovered(printer);
    final lines = raw
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return base.copyWith(
        state: ZebraPrinterState.connected,
        message: 'Status unavailable',
        hardwareStatusLabel: 'unknown',
        connected: true,
      );
    }

    final first = lines.first.split(',');
    // Typical: aaa,b,c,dddd,eee,f,g,h,iii,j,k,l
    final paperOut = _flag(first, 1);
    final paused = _flag(first, 2);
    final bufferFull = first.length > 4
        ? (int.tryParse(first[4].trim()) ?? 0) > 0
        : false;

    var headOpen = false;
    var ribbonOut = false;
    if (lines.length > 1) {
      final second = lines[1].split(',');
      headOpen = _flag(second, 2);
      ribbonOut = _flag(second, 3);
    }

    final ready = !paperOut && !paused && !headOpen && !ribbonOut && !bufferFull;
    final label = _label(
      ready: ready,
      paperOut: paperOut,
      headOpen: headOpen,
      ribbonOut: ribbonOut,
      paused: paused,
      bufferFull: bufferFull,
    );

    return base.copyWith(
      state: ready ? ZebraPrinterState.ready : ZebraPrinterState.degraded,
      message: label,
      connected: true,
      readyToPrint: ready,
      paperOut: paperOut,
      headOpen: headOpen,
      ribbonOut: ribbonOut,
      paused: paused,
      bufferFull: bufferFull,
      hardwareStatusLabel: label,
      clearError: ready,
    );
  }

  static ZebraPrinterStatus fromNativeMap(
    Map<Object?, Object?> map, {
    required ZebraPrinterDescriptor printer,
    ZebraPrinterStatus? previous,
  }) {
    final base = previous ?? ZebraPrinterStatus.discovered(printer);
    final paperOut = map['isPaperOut'] == true || map['paperOut'] == true;
    final headOpen = map['isHeadOpen'] == true || map['headOpen'] == true;
    final ribbonOut = map['isRibbonOut'] == true || map['ribbonOut'] == true;
    final paused = map['isPaused'] == true || map['paused'] == true;
    final bufferFull =
        map['isReceiveBufferFull'] == true || map['bufferFull'] == true;
    final ready = map['isReadyToPrint'] == true ||
        map['readyToPrint'] == true ||
        (!paperOut && !headOpen && !ribbonOut && !paused && !bufferFull);
    final label = (map['label'] as String?)?.trim().isNotEmpty == true
        ? map['label'] as String
        : _label(
            ready: ready,
            paperOut: paperOut,
            headOpen: headOpen,
            ribbonOut: ribbonOut,
            paused: paused,
            bufferFull: bufferFull,
          );

    return base.copyWith(
      state: ready ? ZebraPrinterState.ready : ZebraPrinterState.degraded,
      message: label,
      connected: true,
      readyToPrint: ready,
      paperOut: paperOut,
      headOpen: headOpen,
      ribbonOut: ribbonOut,
      paused: paused,
      bufferFull: bufferFull,
      hardwareStatusLabel: label,
      clearError: ready,
    );
  }

  static bool _flag(List<String> parts, int index) {
    if (index >= parts.length) return false;
    final value = parts[index].trim();
    if (value == '1' || value.toLowerCase() == 'y') return true;
    final parsed = int.tryParse(value);
    return parsed != null && parsed != 0;
  }

  static String _label({
    required bool ready,
    required bool paperOut,
    required bool headOpen,
    required bool ribbonOut,
    required bool paused,
    required bool bufferFull,
  }) {
    if (paperOut) return 'paper_out';
    if (headOpen) return 'head_open';
    if (ribbonOut) return 'ribbon_out';
    if (paused) return 'paused';
    if (bufferFull) return 'buffer_full';
    if (ready) return 'ready';
    return 'not_ready';
  }
}

class ZebraSgd {
  const ZebraSgd._();

  static Uint8List getCommand(String name) {
    // Multi-line SGD form works over TCP raw socket.
    return utf8.encode('! U1 getvar "$name"\r\n');
  }

  static Uint8List setCommand(String name, String value) {
    return utf8.encode('! U1 setvar "$name" "$value"\r\n');
  }

  static Uint8List doCommand(String name, [String value = '']) {
    if (value.isEmpty) {
      return utf8.encode('! U1 do "$name"\r\n');
    }
    return utf8.encode('! U1 do "$name" "$value"\r\n');
  }

  static Uint8List hostStatusCommand() => utf8.encode('~HS\r\n');
}
