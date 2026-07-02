import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dcs_common/dcs_common.dart';

enum CuteLogLevel { trace, debug, info, warning, error }

enum CuteLogScope { certification, lifecycle, matip, socket }

enum CuteMessageDirection { inbound, outbound, internal }

typedef CuteLogSink = FutureOr<void> Function(CuteLogEvent event);

class CuteLogEvent {
  CuteLogEvent({
    required this.level,
    required this.scope,
    required this.message,
    this.direction = CuteMessageDirection.internal,
    this.data = const {},
    this.error,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final CuteLogLevel level;
  final CuteLogScope scope;
  final CuteMessageDirection direction;
  final String message;
  final Map<String, Object?> data;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'scope': scope.name,
    'direction': direction.name,
    'message': message,
    if (data.isNotEmpty) 'data': data,
    if (error != null) 'error': error.toString(),
    if (stackTrace != null) 'stackTrace': stackTrace.toString(),
  };

  @override
  String toString() => jsonEncode(toJson());
}

class CuteLogger {
  CuteLogger({
    List<CuteLogSink> sinks = const [],
    this.minimumLevel = CuteLogLevel.trace,
  }) : _sinks = List.of(sinks);

  final List<CuteLogSink> _sinks;
  final CuteLogLevel minimumLevel;
  final _controller = StreamController<CuteLogEvent>.broadcast();
  final _recent = <CuteLogEvent>[];

  Stream<CuteLogEvent> get stream => _controller.stream;

  List<CuteLogEvent> get recent => List.unmodifiable(_recent);

  void addSink(CuteLogSink sink) {
    _sinks.add(sink);
  }

  Future<void> close() => _controller.close();

  void call(
    CuteLogLevel level,
    CuteLogScope scope,
    String message, {
    CuteMessageDirection direction = CuteMessageDirection.internal,
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;

    final event = CuteLogEvent(
      level: level,
      scope: scope,
      message: message,
      direction: direction,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
    _recent.add(event);
    if (_recent.length > 500) {
      _recent.removeRange(0, _recent.length - 500);
    }
    if (!_controller.isClosed) {
      _controller.add(event);
    }

    developer.log(
      jsonEncode(event.toJson()),
      name: 'dcs_cute.${scope.name}',
      level: _developerLevel(level),
      error: error,
      stackTrace: stackTrace,
    );

    for (final sink in _sinks) {
      Future.sync(() => sink(event)).ignore();
    }
  }

  static int _developerLevel(CuteLogLevel level) {
    return switch (level) {
      CuteLogLevel.trace => 300,
      CuteLogLevel.debug => 500,
      CuteLogLevel.info => 800,
      CuteLogLevel.warning => 900,
      CuteLogLevel.error => 1000,
    };
  }
}

class CuteFileLogSink {
  const CuteFileLogSink({required this.directory, this.filePrefix = 'cute'});

  final Directory directory;
  final String filePrefix;

  Future<void> call(CuteLogEvent event) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final day = event.timestamp.toIso8601String().substring(0, 10);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${filePrefix}_${event.scope.name}_$day.jsonl',
    );
    await file.writeAsString(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
      flush: false,
    );
  }
}

class CuteStandardLogSink {
  const CuteStandardLogSink({required this.store});

  final DcsStandardLogStore store;

  Future<void> call(CuteLogEvent event) {
    return store.writeBoth(
      DcsStandardLogEvent.now(
        module: DcsPackageModule.cute,
        severity: _severity(event.level),
        operation: event.scope.name,
        message: event.message,
        error: event.error,
        stackTrace: event.stackTrace,
        data: {
          'direction': event.direction.name,
          if (event.data.isNotEmpty) 'data': event.data,
        },
      ),
    );
  }

  DcsLogSeverity _severity(CuteLogLevel level) {
    return switch (level) {
      CuteLogLevel.trace => DcsLogSeverity.trace,
      CuteLogLevel.debug => DcsLogSeverity.debug,
      CuteLogLevel.info => DcsLogSeverity.info,
      CuteLogLevel.warning => DcsLogSeverity.warning,
      CuteLogLevel.error => DcsLogSeverity.error,
    };
  }
}
