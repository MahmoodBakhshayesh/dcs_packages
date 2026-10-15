import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dcs_zebra/dcs_zebra.dart';

/// In-memory transport for unit tests.
class FakeZebraTransport implements ZebraTransport {
  FakeZebraTransport({
    this.connectionType = ZebraConnectionType.tcp,
    Map<String, String>? sgdValues,
  }) : sgdValues = Map<String, String>.from(sgdValues ?? const {});

  @override
  final ZebraConnectionType connectionType;

  final Map<String, String> sgdValues;
  final writes = <String>[];
  final _readQueue = <Uint8List?>[];
  var connected = false;
  var failNextWrite = false;
  var failWritesMatching = <String>[];

  void enqueueRead(String? text) {
    if (text == null) {
      _readQueue.add(null);
    } else {
      _readQueue.add(Uint8List.fromList(utf8.encode(text)));
    }
  }

  void enqueueReads(Iterable<String?> texts) {
    for (final text in texts) {
      enqueueRead(text);
    }
  }

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect({Duration? timeout}) async {
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<void> write(Uint8List data, {Duration? timeout}) async {
    if (!connected) {
      throw const ZebraRequestFailure('not connected');
    }
    final text = utf8.decode(data);
    writes.add(text);
    if (failNextWrite) {
      failNextWrite = false;
      throw const ZebraRequestFailure('write failed');
    }
    for (final pattern in failWritesMatching) {
      if (text.contains(pattern)) {
        throw ZebraRequestFailure('write failed: $pattern');
      }
    }

    // Auto-reply SGD getvar from [sgdValues].
    final getMatch =
        RegExp(r'getvar\s+"([^"]+)"', caseSensitive: false).firstMatch(text);
    if (getMatch != null) {
      final name = getMatch.group(1)!;
      final value = sgdValues[name];
      enqueueRead(value == null ? '' : '"$value"');
    }
  }

  @override
  Future<Uint8List?> read({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_readQueue.isEmpty) return null;
    return _readQueue.removeAt(0);
  }
}
