import 'dart:async';
import 'dart:typed_data';

import '../zebra_models.dart';

/// Low-level transport used by [ZebraPrinter].
abstract class ZebraTransport {
  ZebraConnectionType get connectionType;

  bool get isConnected;

  Future<void> connect({Duration? timeout});

  Future<void> disconnect();

  Future<void> write(Uint8List data, {Duration? timeout});

  /// Optional read with timeout. Returns null on timeout / no data.
  Future<Uint8List?> read({Duration timeout = const Duration(seconds: 2)});
}
