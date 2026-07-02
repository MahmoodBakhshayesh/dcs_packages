// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'dcs_adapters.dart';

/// Classified outcome for a request/response device command.
enum DcsDeviceResponseStatus { ok, error, unknown, timeout }

typedef DcsResponseClassifier =
    DcsDeviceResponseStatus Function(Uint8List bytes, String text);

/// Options for one queued request.
class DcsDeviceRequestOptions {
  const DcsDeviceRequestOptions({
    this.timeout = const Duration(seconds: 2),
    this.quietWindow = const Duration(milliseconds: 150),
    this.encoding = utf8,
    this.framed = false,
    this.classifier = defaultClassifier,
  });

  /// Hard deadline for receiving a response.
  final Duration timeout;

  /// Raw responses are considered complete after this idle period.
  final Duration quietWindow;

  final Encoding encoding;

  /// Parses STX/ETX framed responses and unescapes DLE bytes.
  final bool framed;

  final DcsResponseClassifier classifier;

  static DcsDeviceResponseStatus defaultClassifier(
    Uint8List bytes,
    String text,
  ) {
    if (bytes.isEmpty) return DcsDeviceResponseStatus.timeout;

    final normalized = text.toUpperCase();
    if (normalized.contains('ERR') ||
        normalized.contains('ERROR') ||
        normalized.contains('NOK')) {
      return DcsDeviceResponseStatus.error;
    }
    if (normalized.contains('OK') ||
        normalized.contains('EPOK') ||
        normalized.contains('ESOK')) {
      return DcsDeviceResponseStatus.ok;
    }
    return DcsDeviceResponseStatus.unknown;
  }
}

/// Rich result returned by a queued command.
class DcsDeviceResponse {
  const DcsDeviceResponse({
    required this.status,
    required this.bytes,
    required this.text,
    required this.timedOut,
  });

  final DcsDeviceResponseStatus status;
  final Uint8List bytes;
  final String text;
  final bool timedOut;

  bool get isOk => status == DcsDeviceResponseStatus.ok;
}

/// Serializes request/response traffic for devices that answer one command at a time.
class DcsDeviceRequestQueue {
  DcsDeviceRequestQueue(
    this._session, {
    DcsDeviceRequestOptions defaultOptions = const DcsDeviceRequestOptions(),
  }) : _defaultOptions = defaultOptions;

  final DcsDeviceSession _session;
  final DcsDeviceRequestOptions _defaultOptions;
  Future<void> _tail = Future<void>.value();

  Future<DcsDeviceResponse> sendText(
    String command, {
    DcsDeviceRequestOptions? options,
  }) {
    final requestOptions = options ?? _defaultOptions;
    return sendBytes(
      requestOptions.encoding.encode(command),
      options: requestOptions,
    );
  }

  Future<DcsDeviceResponse> sendBytes(
    List<int> command, {
    DcsDeviceRequestOptions? options,
  }) {
    final completer = Completer<DcsDeviceResponse>();
    final requestOptions = options ?? _defaultOptions;

    _tail = _tail
        .then((_) async {
          try {
            completer.complete(await _execute(command, requestOptions));
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .catchError((Object _) {});

    return completer.future;
  }

  Future<DcsDeviceResponse> _execute(
    List<int> command,
    DcsDeviceRequestOptions options,
  ) async {
    final bytes = await _captureResponse(command, options);
    final responseBytes = Uint8List.fromList(bytes ?? const []);
    final text = _decode(options.encoding, responseBytes);
    final status = bytes == null
        ? DcsDeviceResponseStatus.timeout
        : options.classifier(responseBytes, text);

    return DcsDeviceResponse(
      status: status,
      bytes: responseBytes,
      text: text,
      timedOut: bytes == null,
    );
  }

  Future<List<int>?> _captureResponse(
    List<int> command,
    DcsDeviceRequestOptions options,
  ) async {
    final completer = Completer<List<int>?>();
    final buffer = <int>[];
    final frameParser = _DcsFrameParser();
    Timer? quietTimer;
    late final StreamSubscription<List<int>> subscription;

    void complete(List<int>? bytes) {
      if (completer.isCompleted) return;
      quietTimer?.cancel();
      completer.complete(bytes);
    }

    final timeoutTimer = Timer(options.timeout, () => complete(null));

    void markRawData() {
      quietTimer?.cancel();
      quietTimer = Timer(
        options.quietWindow,
        () => complete(List<int>.of(buffer)),
      );
    }

    subscription = _session.data.listen((chunk) {
      if (options.framed) {
        final frame = frameParser.add(chunk);
        if (frame != null) {
          complete(frame);
        }
        return;
      }

      buffer.addAll(chunk);
      if (buffer.isNotEmpty) {
        markRawData();
      }
    }, onError: completer.completeError);

    try {
      await _session.write(command);
      return await completer.future;
    } finally {
      timeoutTimer.cancel();
      quietTimer?.cancel();
      await subscription.cancel();
    }
  }
}

String _decode(Encoding encoding, Uint8List bytes) {
  try {
    return encoding.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes);
  }
}

class _DcsFrameParser {
  static const _stx = 0x02;
  static const _etx = 0x03;
  static const _dle = 0x10;

  final _buffer = <int>[];
  var _inFrame = false;
  var _escaped = false;

  List<int>? add(List<int> chunk) {
    for (final byte in chunk) {
      if (!_inFrame) {
        if (byte == _stx) {
          _buffer.clear();
          _inFrame = true;
          _escaped = false;
        }
        continue;
      }

      if (_escaped) {
        _buffer.add(byte);
        _escaped = false;
        continue;
      }

      if (byte == _dle) {
        _escaped = true;
        continue;
      }

      if (byte == _etx) {
        final frame = List<int>.of(_buffer);
        _buffer.clear();
        _inFrame = false;
        return frame;
      }

      _buffer.add(byte);
    }

    return null;
  }
}
