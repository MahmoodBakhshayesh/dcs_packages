import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dcs_common/dcs_common.dart';

import 'zebra_models.dart';

typedef ZebraLogSink = FutureOr<void> Function(ZebraLogEvent event);

class ZebraLogEvent {
  ZebraLogEvent({
    required this.level,
    required this.scope,
    required this.message,
    this.direction = ZebraMessageDirection.internal,
    this.printerId,
    this.payload,
    this.data = const {},
    this.error,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final ZebraLogLevel level;
  final ZebraLogScope scope;
  final ZebraMessageDirection direction;
  final String message;
  final String? printerId;
  final String? payload;
  final Map<String, Object?> data;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  Map<String, Object?> toJson({bool includePayload = true}) => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'scope': scope.name,
        'direction': direction.name,
        'message': message,
        if (printerId != null) 'printerId': printerId,
        if (includePayload && payload != null) 'payload': payload,
        if (data.isNotEmpty) 'data': data,
        if (error != null) 'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      };

  @override
  String toString() => jsonEncode(toJson());
}

class ZebraLogger {
  ZebraLogger({
    List<ZebraLogSink> sinks = const [],
    this.minimumLevel = ZebraLogLevel.trace,
    this.includePayloadInDeveloperLog = false,
  }) : _sinks = List.of(sinks);

  final List<ZebraLogSink> _sinks;
  final ZebraLogLevel minimumLevel;
  final bool includePayloadInDeveloperLog;
  final _controller = StreamController<ZebraLogEvent>.broadcast();
  final _recent = <ZebraLogEvent>[];

  Stream<ZebraLogEvent> get stream => _controller.stream;

  List<ZebraLogEvent> get recent => List.unmodifiable(_recent);

  Future<void> close() => _controller.close();

  void addSink(ZebraLogSink sink) {
    _sinks.add(sink);
  }

  void call(
    ZebraLogLevel level,
    ZebraLogScope scope,
    String message, {
    ZebraMessageDirection direction = ZebraMessageDirection.internal,
    String? printerId,
    String? payload,
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;

    final event = ZebraLogEvent(
      level: level,
      scope: scope,
      direction: direction,
      message: message,
      printerId: printerId,
      payload: payload,
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
      jsonEncode(event.toJson(includePayload: includePayloadInDeveloperLog)),
      name: 'dcs_zebra.${scope.name}',
      level: _developerLevel(level),
      error: error,
      stackTrace: stackTrace,
    );

    for (final sink in _sinks) {
      Future.sync(() => sink(event)).ignore();
    }
  }

  static int _developerLevel(ZebraLogLevel level) {
    return switch (level) {
      ZebraLogLevel.trace => 300,
      ZebraLogLevel.debug => 500,
      ZebraLogLevel.info => 800,
      ZebraLogLevel.warning => 900,
      ZebraLogLevel.error => 1000,
    };
  }
}

class ZebraFileLogSink {
  const ZebraFileLogSink({
    required this.directory,
    this.includePayload = true,
    this.filePrefix = 'zebra',
  });

  final Directory directory;
  final bool includePayload;
  final String filePrefix;

  Future<void> call(ZebraLogEvent event) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final day = event.timestamp.toIso8601String().substring(0, 10);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${filePrefix}_${event.scope.name}_$day.jsonl',
    );
    await file.writeAsString(
      '${jsonEncode(event.toJson(includePayload: includePayload))}\n',
      mode: FileMode.append,
      flush: false,
    );
  }
}

class ZebraStandardLogSink {
  const ZebraStandardLogSink({
    required this.store,
    this.includePayload = true,
  });

  final DcsStandardLogStore store;
  final bool includePayload;

  Future<void> call(ZebraLogEvent event) {
    return store.writeBoth(
      DcsStandardLogEvent.now(
        module: DcsPackageModule.zebra,
        severity: _severity(event.level),
        operation: event.scope.name,
        deviceId: event.printerId,
        message: event.message,
        error: event.error,
        stackTrace: event.stackTrace,
        data: {
          'direction': event.direction.name,
          if (event.data.isNotEmpty) 'data': event.data,
          if (includePayload && event.payload != null) 'payload': event.payload,
        },
      ),
    );
  }

  DcsLogSeverity _severity(ZebraLogLevel level) {
    return switch (level) {
      ZebraLogLevel.trace => DcsLogSeverity.trace,
      ZebraLogLevel.debug => DcsLogSeverity.debug,
      ZebraLogLevel.info => DcsLogSeverity.info,
      ZebraLogLevel.warning => DcsLogSeverity.warning,
      ZebraLogLevel.error => DcsLogSeverity.error,
    };
  }
}
