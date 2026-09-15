/// Shared contracts used by the DCS app and companion packages.
library;

import 'dart:convert';
import 'dart:io';

enum DcsDeviceKind {
  boardingPassPrinter,
  bagTagPrinter,
  documentPrinter,
  barcodeScanner,
  passportScanner,
  scale,
  display,
  biometric,
  unknown,
}

enum DcsTransportKind {
  localSerial,
  localUsb,
  localNetwork,
  cuppsPlatform,
  cuteMatip,
  hostApi,
  zebraNetwork,
  zebraBluetooth,
  zebraUsb,
  simulator,
  unknown,
}

enum DcsRuntimeState {
  idle,
  configured,
  discovering,
  connecting,
  connected,
  authenticating,
  ready,
  busy,
  degraded,
  disconnected,
  failed,
}

enum DcsLogSeverity { trace, debug, info, warning, error }

enum DcsPackageModule {
  app,
  common,
  deviceUtil,
  cupps,
  cute,
  zebra,
  documents,
  bcbp,
  mrz,
  baggage,
  host,
  simulator,
  certification,
}

class DcsEndpoint {
  const DcsEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  bool get isValid => host.trim().isNotEmpty && port > 0 && port <= 65535;

  @override
  String toString() => '$host:$port';
}

class DcsRuntimeComponent {
  const DcsRuntimeComponent({
    required this.id,
    required this.label,
    required this.module,
    this.deviceKind = DcsDeviceKind.unknown,
    this.transport = DcsTransportKind.unknown,
    this.endpoint,
  });

  final String id;
  final String label;
  final DcsPackageModule module;
  final DcsDeviceKind deviceKind;
  final DcsTransportKind transport;
  final DcsEndpoint? endpoint;
}

class DcsRuntimeStatus {
  const DcsRuntimeStatus({
    required this.component,
    required this.state,
    required this.message,
    required this.updatedAt,
    this.error,
  });

  factory DcsRuntimeStatus.now({
    required DcsRuntimeComponent component,
    required DcsRuntimeState state,
    required String message,
    Object? error,
  }) {
    return DcsRuntimeStatus(
      component: component,
      state: state,
      message: message,
      updatedAt: DateTime.now(),
      error: error,
    );
  }

  final DcsRuntimeComponent component;
  final DcsRuntimeState state;
  final String message;
  final DateTime updatedAt;
  final Object? error;

  bool get needsAttention =>
      state == DcsRuntimeState.degraded ||
      state == DcsRuntimeState.disconnected ||
      state == DcsRuntimeState.failed;
}

class DcsRuntimeLogEvent {
  const DcsRuntimeLogEvent({
    required this.module,
    required this.severity,
    required this.message,
    required this.timestamp,
    this.componentId,
    this.error,
    this.data = const {},
  });

  factory DcsRuntimeLogEvent.now({
    required DcsPackageModule module,
    required DcsLogSeverity severity,
    required String message,
    String? componentId,
    Object? error,
    Map<String, Object?> data = const {},
  }) {
    return DcsRuntimeLogEvent(
      module: module,
      severity: severity,
      message: message,
      timestamp: DateTime.now(),
      componentId: componentId,
      error: error,
      data: data,
    );
  }

  final DcsPackageModule module;
  final DcsLogSeverity severity;
  final String message;
  final DateTime timestamp;
  final String? componentId;
  final Object? error;
  final Map<String, Object?> data;
}

enum DcsLogFileFormat { jsonl, readable }

class DcsStandardLogEvent {
  const DcsStandardLogEvent({
    required this.module,
    required this.severity,
    required this.message,
    required this.timestamp,
    required this.operation,
    this.deviceId,
    this.operationId,
    this.componentId,
    this.error,
    this.stackTrace,
    this.data = const {},
  });

  factory DcsStandardLogEvent.now({
    required DcsPackageModule module,
    required DcsLogSeverity severity,
    required String operation,
    required String message,
    String? deviceId,
    String? operationId,
    String? componentId,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    return DcsStandardLogEvent(
      module: module,
      severity: severity,
      operation: operation,
      message: message,
      timestamp: DateTime.now(),
      deviceId: deviceId,
      operationId: operationId,
      componentId: componentId,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );
  }

  final DcsPackageModule module;
  final DcsLogSeverity severity;
  final String operation;
  final String message;
  final DateTime timestamp;
  final String? deviceId;
  final String? operationId;
  final String? componentId;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'module': module.name,
        'severity': severity.name,
        'operation': operation,
        'message': message,
        if (deviceId != null) 'deviceId': deviceId,
        if (operationId != null) 'operationId': operationId,
        if (componentId != null) 'componentId': componentId,
        if (data.isNotEmpty) 'data': data,
        if (error != null) 'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      };

  String toReadableLine() {
    final buffer = StringBuffer()
      ..write(timestamp.toIso8601String())
      ..write(' [${severity.name.toUpperCase()}]')
      ..write(' module=${module.name}')
      ..write(' operation=$operation');
    if (deviceId != null) buffer.write(' device=$deviceId');
    if (operationId != null) buffer.write(' operationId=$operationId');
    if (componentId != null) buffer.write(' component=$componentId');
    buffer.write(' | $message');
    if (data.isNotEmpty) buffer.write(' | data=${jsonEncode(data)}');
    if (error != null) buffer.write(' | error=$error');
    return buffer.toString();
  }
}

class DcsStandardLogFile {
  const DcsStandardLogFile({
    required this.path,
    required this.name,
    required this.module,
    required this.deviceId,
    required this.operation,
    required this.format,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final DcsPackageModule module;
  final String deviceId;
  final String operation;
  final DcsLogFileFormat format;
  final DateTime modifiedAt;
  final int sizeBytes;
}

class DcsStandardLogStore {
  const DcsStandardLogStore({required this.rootDirectory});

  final Directory rootDirectory;

  Future<File> write(
    DcsStandardLogEvent event, {
    DcsLogFileFormat format = DcsLogFileFormat.jsonl,
  }) async {
    final file = _fileFor(event, format);
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    final line = switch (format) {
      DcsLogFileFormat.jsonl => jsonEncode(event.toJson()),
      DcsLogFileFormat.readable => event.toReadableLine(),
    };
    await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
    return file;
  }

  Future<void> writeBoth(DcsStandardLogEvent event) async {
    await write(event, format: DcsLogFileFormat.jsonl);
    await write(event, format: DcsLogFileFormat.readable);
  }

  Future<List<DcsStandardLogFile>> list() async {
    if (!rootDirectory.existsSync()) return const [];
    final files = <DcsStandardLogFile>[];
    await for (final entity in rootDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      final format = name.endsWith('.jsonl')
          ? DcsLogFileFormat.jsonl
          : name.endsWith('.log')
              ? DcsLogFileFormat.readable
              : null;
      if (format == null) continue;
      final stat = await entity.stat();
      files.add(
        DcsStandardLogFile(
          path: entity.path,
          name: name,
          module: _moduleFromPath(entity.path),
          deviceId: _segmentFromName(name, 1),
          operation: _segmentFromName(name, 2),
          format: format,
          modifiedAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }
    files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return files;
  }

  Future<String> read(DcsStandardLogFile logFile) {
    return File(logFile.path).readAsString();
  }

  Future<void> delete(DcsStandardLogFile logFile) async {
    final file = File(logFile.path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<File> exportTo(DcsStandardLogFile logFile, Directory targetDirectory) async {
    if (!targetDirectory.existsSync()) {
      await targetDirectory.create(recursive: true);
    }
    final target = File('${targetDirectory.path}${Platform.pathSeparator}${logFile.name}');
    return File(logFile.path).copy(target.path);
  }

  File _fileFor(DcsStandardLogEvent event, DcsLogFileFormat format) {
    final day = event.timestamp.toIso8601String().substring(0, 10);
    final device = _safeSegment(event.deviceId ?? 'no-device');
    final operation = _safeSegment(event.operation);
    final extension = format == DcsLogFileFormat.jsonl ? 'jsonl' : 'log';
    return File(
      '${rootDirectory.path}${Platform.pathSeparator}'
      '${event.module.name}${Platform.pathSeparator}'
      '${day}_${device}_$operation.$extension',
    );
  }

  DcsPackageModule _moduleFromPath(String path) {
    final separator = Platform.pathSeparator;
    final parts = path.split(separator);
    final rootParts = rootDirectory.path.split(separator);
    final moduleName = parts.length > rootParts.length ? parts[rootParts.length] : '';
    return DcsPackageModule.values.firstWhere(
      (module) => module.name == moduleName,
      orElse: () => DcsPackageModule.app,
    );
  }

  String _segmentFromName(String name, int index) {
    final stem = name.replaceAll(RegExp(r'\.(jsonl|log)$'), '');
    final parts = stem.split('_');
    return parts.length > index ? parts[index] : '';
  }
}

String _safeSegment(String value) {
  final sanitized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9.-]+'), '-');
  return sanitized.isEmpty ? 'unknown' : sanitized;
}

String _basename(String path) {
  final separator = Platform.pathSeparator;
  final index = path.lastIndexOf(separator);
  return index == -1 ? path : path.substring(index + 1);
}

class DcsRuntimeIssue {
  const DcsRuntimeIssue({
    required this.id,
    required this.module,
    required this.severity,
    required this.message,
    this.blocking = false,
  });

  final String id;
  final DcsPackageModule module;
  final DcsLogSeverity severity;
  final String message;
  final bool blocking;
}
