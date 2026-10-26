// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'dcs_adapters.dart';
import 'dcs_models.dart';

/// Classified outcome for a request/response device command.
enum DcsDeviceResponseStatus { ok, error, unknown, timeout }

typedef DcsResponseClassifier = DcsDeviceResponseStatus Function(Uint8List bytes, String text);

/// Options for one queued request.
class DcsDeviceRequestOptions {
  const DcsDeviceRequestOptions({
    this.timeout = const Duration(seconds: 2),
    this.quietWindow = const Duration(milliseconds: 150),
    this.encoding = utf8,
    this.framed = false,
    this.protocolMode,
    this.waitForResponse = true,
    this.postWriteHold = Duration.zero,
    this.classifier = defaultClassifier,
  });

  /// Hard deadline for receiving a response.
  final Duration timeout;

  /// Raw responses are considered complete after this idle period.
  final Duration quietWindow;

  final Encoding encoding;

  /// Parses STX/ETX framed responses and unescapes DLE bytes.
  ///
  /// Prefer [protocolMode]. When null, [framed] maps to
  /// [DcsProtocolMode.framed] / [DcsProtocolMode.none].
  final bool framed;

  /// Full protocol mode. When set, overrides [framed].
  final DcsProtocolMode? protocolMode;

  /// When false, still frames + writes on the per-device queue but does not
  /// wait for an AEA ack (ATB CP# often never replies).
  final bool waitForResponse;

  /// Optional extra hold after write/response before releasing the per-device
  /// queue. Prefer waiting for a real OK/error (`waitForResponse: true`) —
  /// use this only when a device never replies.
  final Duration postWriteHold;

  final DcsResponseClassifier classifier;

  DcsProtocolMode get resolvedProtocolMode {
    if (protocolMode != null) return protocolMode!;
    return framed ? DcsProtocolMode.framed : DcsProtocolMode.none;
  }

  static DcsDeviceResponseStatus defaultClassifier(Uint8List bytes, String text) {
    if (bytes.isEmpty) return DcsDeviceResponseStatus.timeout;

    final normalized = text.toUpperCase();

    // Explicit AEA/HDC error verbs only — never match EP params like ERR3IGN.
    if (_hasHardAeaError(normalized)) {
      return DcsDeviceResponseStatus.error;
    }

    // Success verbs / OK payloads (HDCEPOK, HDCPTOK, HDCMXOK, STATUSOK, …).
    if (normalized.contains('EPOK') ||
        normalized.contains('ESOK') ||
        normalized.contains('PTOK') ||
        normalized.contains('PROK') ||
        normalized.contains('OK')) {
      return DcsDeviceResponseStatus.ok;
    }
    return DcsDeviceResponseStatus.unknown;
  }

  /// True for busy / in-progress device replies (safe to retry).
  static bool isBusyError(String text) {
    final n = text.toUpperCase();
    return n.contains('HDCERR7') || RegExp(r'(^|[^A-Z0-9])ERR7([^A-Z]|$)').hasMatch(n);
  }

  static bool _hasHardAeaError(String normalized) {
    if (normalized.contains('HDCERR') ||
        normalized.contains('PRERR') ||
        normalized.contains('PTERR') ||
        normalized.contains('BTPERR') ||
        normalized.contains('ATBERR') ||
        normalized.contains('BGRERR') ||
        normalized.contains('ERROR')) {
      return true;
    }
    // AEA ERR\d (ERR3/5/6/7…). Print-steering can prefix the code
    // (`CHKINERR3`, `TICKTERR2`, `BOARDERR6`) — do not require a non-alnum
    // boundary before ERR. Strip EP params ERR3IGN / ERR5PRT first.
    final withoutParams = normalized.replaceAll(RegExp(r'ERR\d(?:IGN|PRT)'), '');
    return RegExp(r'ERR\d').hasMatch(withoutParams);
  }
}

/// Rich result returned by a queued command.
class DcsDeviceResponse {
  const DcsDeviceResponse({required this.status, required this.bytes, required this.text, required this.timedOut});

  final DcsDeviceResponseStatus status;
  final Uint8List bytes;
  final String text;
  final bool timedOut;

  bool get isOk => status == DcsDeviceResponseStatus.ok;
}

/// Depth of one device's request queue: [waiting] commands behind the [running] one.
class DcsQueueState {
  const DcsQueueState({this.waiting = 0, this.running = 0});

  /// Commands queued behind the one on the wire.
  final int waiting;

  /// Commands on the wire waiting for their response (0 or 1 — the queue is strictly serial).
  final int running;

  int get depth => waiting + running;

  bool get isIdle => depth == 0;

  @override
  bool operator ==(Object other) => other is DcsQueueState && other.waiting == waiting && other.running == running;

  @override
  int get hashCode => Object.hash(waiting, running);

  @override
  String toString() => 'DcsQueueState(waiting: $waiting, running: $running)';
}

/// Serializes request/response traffic for devices that answer one command at a time.
///
/// Observe the queue with [state] / [states]; pass `onStart` to a send to learn when that command actually reaches
/// the device (after everything queued before it finished).
class DcsDeviceRequestQueue {
  DcsDeviceRequestQueue(
    this._session, {
    DcsDeviceRequestOptions defaultOptions = const DcsDeviceRequestOptions(),
    void Function(DcsQueueState state)? onStateChanged,
  }) : _defaultOptions = defaultOptions,
       _onStateChanged = onStateChanged;

  final DcsDeviceSession _session;
  final DcsDeviceRequestOptions _defaultOptions;
  final void Function(DcsQueueState state)? _onStateChanged;
  final _states = StreamController<DcsQueueState>.broadcast(sync: true);
  Future<void> _tail = Future<void>.value();
  int _waiting = 0;
  int _running = 0;

  /// Current depth.
  DcsQueueState get state => DcsQueueState(waiting: _waiting, running: _running);

  /// Every depth change (enqueue, start, finish).
  Stream<DcsQueueState> get states => _states.stream;

  void _emit() {
    final next = state;
    _onStateChanged?.call(next);
    if (!_states.isClosed) _states.add(next);
  }

  Future<DcsDeviceResponse> sendText(
    String command, {
    DcsDeviceRequestOptions? options,
    void Function()? onStart,
  }) {
    final requestOptions = options ?? _defaultOptions;
    return sendBytes(requestOptions.encoding.encode(command), options: requestOptions, onStart: onStart);
  }

  /// Queues [command]; [onStart] runs right before it is written (its turn on the device).
  Future<DcsDeviceResponse> sendBytes(
    List<int> command, {
    DcsDeviceRequestOptions? options,
    void Function()? onStart,
  }) {
    final completer = Completer<DcsDeviceResponse>();
    final requestOptions = options ?? _defaultOptions;
    _waiting++;
    _emit();

    _tail = _tail
        .then((_) async {
          _waiting--;
          _running++;
          _emit();
          try {
            try {
              onStart?.call();
            } catch (_) {
              // Observer errors must not break the device queue.
            }
            completer.complete(await _execute(command, requestOptions));
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          } finally {
            _running--;
            _emit();
          }
        })
        .catchError((Object _) {});

    return completer.future;
  }

  /// Stops emitting [states] (the session closed).
  void close() {
    if (!_states.isClosed) _states.close();
  }

  Future<DcsDeviceResponse> _execute(List<int> command, DcsDeviceRequestOptions options) async {
    final wire = _encodeOutbound(command, options.resolvedProtocolMode);
    late final DcsDeviceResponse response;
    if (!options.waitForResponse) {
      await _session.write(wire);
      response = DcsDeviceResponse(status: DcsDeviceResponseStatus.ok, bytes: Uint8List(0), text: '', timedOut: false);
    } else {
      final bytes = await _captureResponse(wire, options);
      final responseBytes = Uint8List.fromList(bytes ?? const []);
      final text = _decode(options.encoding, responseBytes);
      final status = bytes == null ? DcsDeviceResponseStatus.timeout : options.classifier(responseBytes, text);

      response = DcsDeviceResponse(status: status, bytes: responseBytes, text: text, timedOut: bytes == null);
    }

    // Hold the per-device queue so the next CP#/command cannot race the ATB.
    final hold = options.postWriteHold;
    if (hold > Duration.zero) {
      await Future<void>.delayed(hold);
    }
    return response;
  }

  Future<List<int>?> _captureResponse(List<int> command, DcsDeviceRequestOptions options) async {
    final completer = Completer<List<int>?>();
    final buffer = <int>[];
    final frameParser = _DcsFrameParser(keepPreStx: true);
    Timer? quietTimer;
    late final StreamSubscription<List<int>> subscription;
    final mode = options.resolvedProtocolMode;

    void complete(List<int>? bytes) {
      if (completer.isCompleted) return;
      quietTimer?.cancel();
      completer.complete(bytes);
    }

    final timeoutTimer = Timer(options.timeout, () => complete(null));

    void markRawData() {
      quietTimer?.cancel();
      quietTimer = Timer(options.quietWindow, () => complete(List<int>.of(buffer)));
    }

    subscription = _session.data.listen((chunk) {
      switch (mode) {
        case DcsProtocolMode.framed:
          final frame = frameParser.add(chunk);
          if (frame != null) {
            complete(frame);
          }
          return;
        case DcsProtocolMode.auto:
          final frame = frameParser.add(chunk);
          if (frame != null) {
            complete(frame);
            return;
          }
          if (!frameParser.sawStx) {
            buffer
              ..clear()
              ..addAll(frameParser.preStxBytes);
            if (buffer.isNotEmpty) {
              markRawData();
            }
          }
          return;
        case DcsProtocolMode.none:
          buffer.addAll(chunk);
          if (buffer.isNotEmpty) {
            markRawData();
          }
          return;
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

List<int> _encodeOutbound(List<int> command, DcsProtocolMode mode) {
  return DcsAeaFraming.encodeOutbound(command, mode);
}

/// Frames AEA payloads with STX/ETX (+ DLE escape) for `framed` and `auto`.
///
/// `none` leaves bytes unchanged. Already-framed payloads are not double-wrapped.
abstract final class DcsAeaFraming {
  static const stx = 0x02;
  static const etx = 0x03;
  static const dle = 0x10;

  static List<int> encodeOutbound(List<int> command, DcsProtocolMode mode) {
    if (mode == DcsProtocolMode.none) return command;
    if (command.isEmpty) {
      return const [stx, etx];
    }
    // Already framed — do not double-wrap.
    if (command.first == stx && command.last == etx) {
      return command;
    }
    final escaped = <int>[stx];
    for (final byte in command) {
      if (byte == stx || byte == etx || byte == dle) {
        escaped.add(dle);
      }
      escaped.add(byte);
    }
    escaped.add(etx);
    return escaped;
  }
}

/// Compatibility alias for [DcsAeaFraming.encodeOutbound].
List<int> dcsEncodeAeaOutbound(List<int> command, DcsProtocolMode mode) {
  return DcsAeaFraming.encodeOutbound(command, mode);
}

String _decode(Encoding encoding, Uint8List bytes) {
  try {
    return encoding.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes);
  }
}

class _DcsFrameParser {
  _DcsFrameParser({this.keepPreStx = false});

  static const stx = 0x02;
  static const etx = 0x03;
  static const dle = 0x10;

  final bool keepPreStx;
  final _buffer = <int>[];
  final preStxBytes = <int>[];
  var _inFrame = false;
  var _escaped = false;
  var sawStx = false;

  List<int>? add(List<int> chunk) {
    for (final byte in chunk) {
      if (!_inFrame) {
        if (byte == stx) {
          _buffer.clear();
          _inFrame = true;
          _escaped = false;
          sawStx = true;
          if (keepPreStx) {
            preStxBytes.clear();
          }
        } else if (keepPreStx && !sawStx) {
          preStxBytes.add(byte);
        }
        continue;
      }

      if (_escaped) {
        _buffer.add(byte);
        _escaped = false;
        continue;
      }

      if (byte == dle) {
        _escaped = true;
        continue;
      }

      if (byte == etx) {
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
