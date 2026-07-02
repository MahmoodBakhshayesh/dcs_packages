import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dcs_common/dcs_common.dart';

import 'cupps_models.dart';

typedef CuppsLogSink = FutureOr<void> Function(CuppsLogEvent event);

class CuppsLogEvent {
  CuppsLogEvent({
    required this.level,
    required this.scope,
    required this.message,
    this.direction = CuppsMessageDirection.internal,
    this.deviceId,
    this.messageId,
    this.xml,
    this.data = const {},
    this.error,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final CuppsLogLevel level;
  final CuppsLogScope scope;
  final CuppsMessageDirection direction;
  final String message;
  final String? deviceId;
  final int? messageId;
  final String? xml;
  final Map<String, Object?> data;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  Map<String, Object?> toJson({bool includeXml = true}) => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'scope': scope.name,
    'direction': direction.name,
    'message': message,
    if (deviceId != null) 'deviceId': deviceId,
    if (messageId != null) 'messageId': messageId,
    if (includeXml && xml != null) 'xml': xml,
    if (data.isNotEmpty) 'data': data,
    if (error != null) 'error': error.toString(),
    if (stackTrace != null) 'stackTrace': stackTrace.toString(),
  };

  @override
  String toString() => jsonEncode(toJson());
}

class CuppsLogger {
  CuppsLogger({
    List<CuppsLogSink> sinks = const [],
    this.minimumLevel = CuppsLogLevel.trace,
    this.includeXmlInDeveloperLog = false,
  }) : _sinks = List.of(sinks);

  final List<CuppsLogSink> _sinks;
  final CuppsLogLevel minimumLevel;
  final bool includeXmlInDeveloperLog;
  final _controller = StreamController<CuppsLogEvent>.broadcast();
  final _recent = <CuppsLogEvent>[];

  Stream<CuppsLogEvent> get stream => _controller.stream;

  List<CuppsLogEvent> get recent => List.unmodifiable(_recent);

  Future<void> close() => _controller.close();

  void addSink(CuppsLogSink sink) {
    _sinks.add(sink);
  }

  void call(
    CuppsLogLevel level,
    CuppsLogScope scope,
    String message, {
    CuppsMessageDirection direction = CuppsMessageDirection.internal,
    String? deviceId,
    int? messageId,
    String? xml,
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;

    final event = CuppsLogEvent(
      level: level,
      scope: scope,
      direction: direction,
      message: message,
      deviceId: deviceId,
      messageId: messageId,
      xml: xml,
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
      jsonEncode(event.toJson(includeXml: includeXmlInDeveloperLog)),
      name: 'dcs_cupps.${scope.name}',
      level: _developerLevel(level),
      error: error,
      stackTrace: stackTrace,
    );

    for (final sink in _sinks) {
      Future.sync(() => sink(event)).ignore();
    }
  }

  static int _developerLevel(CuppsLogLevel level) {
    return switch (level) {
      CuppsLogLevel.trace => 300,
      CuppsLogLevel.debug => 500,
      CuppsLogLevel.info => 800,
      CuppsLogLevel.warning => 900,
      CuppsLogLevel.error => 1000,
    };
  }
}

class CuppsFileLogSink {
  const CuppsFileLogSink({
    required this.directory,
    this.includeXml = true,
    this.filePrefix = 'cupps',
  });

  final Directory directory;
  final bool includeXml;
  final String filePrefix;

  Future<void> call(CuppsLogEvent event) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final day = event.timestamp.toIso8601String().substring(0, 10);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${filePrefix}_${event.scope.name}_$day.jsonl',
    );
    await file.writeAsString(
      '${jsonEncode(event.toJson(includeXml: includeXml))}\n',
      mode: FileMode.append,
      flush: false,
    );
  }
}

class CuppsStandardLogSink {
  const CuppsStandardLogSink({
    required this.store,
    this.includeXml = true,
  });

  final DcsStandardLogStore store;
  final bool includeXml;

  Future<void> call(CuppsLogEvent event) {
    return store.writeBoth(
      DcsStandardLogEvent.now(
        module: DcsPackageModule.cupps,
        severity: _severity(event.level),
        operation: event.scope.name,
        deviceId: event.deviceId,
        operationId: event.messageId?.toString(),
        message: event.message,
        error: event.error,
        stackTrace: event.stackTrace,
        data: {
          'direction': event.direction.name,
          if (event.data.isNotEmpty) 'data': event.data,
          if (includeXml && event.xml != null) 'xml': event.xml,
        },
      ),
    );
  }

  DcsLogSeverity _severity(CuppsLogLevel level) {
    return switch (level) {
      CuppsLogLevel.trace => DcsLogSeverity.trace,
      CuppsLogLevel.debug => DcsLogSeverity.debug,
      CuppsLogLevel.info => DcsLogSeverity.info,
      CuppsLogLevel.warning => DcsLogSeverity.warning,
      CuppsLogLevel.error => DcsLogSeverity.error,
    };
  }
}
