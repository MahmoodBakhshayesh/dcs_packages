// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'transport/method_channel_zebra_transport.dart';
import 'transport/tcp_zebra_transport.dart';
import 'transport/zebra_transport.dart';
import 'zebra_logger.dart';
import 'zebra_models.dart';
import 'zebra_status_parser.dart';

typedef ZebraStatusUpdater = void Function(ZebraPrinterStatus status);

/// Single Zebra printer session (TCP / Bluetooth / USB).
class ZebraPrinter {
  ZebraPrinter({
    required this.descriptor,
    required ZebraLogger logger,
    required ZebraStatusUpdater onStatus,
    ZebraConnectionOptions options = const ZebraConnectionOptions(),
    ZebraTransport? transport,
  })  : _logger = logger,
        _onStatus = onStatus,
        _options = options,
        _transport = transport,
        _status = ZebraPrinterStatus.discovered(descriptor);

  final ZebraPrinterDescriptor descriptor;
  final ZebraLogger _logger;
  final ZebraStatusUpdater _onStatus;
  final ZebraConnectionOptions _options;
  ZebraTransport? _transport;
  ZebraPrinterStatus _status;
  _ZebraBatchRun? _batchRun;

  String get id => descriptor.id;

  ZebraPrinterRole get role => descriptor.role;

  ZebraPrinterStatus get status => _status;

  bool get isConnected => _transport?.isConnected == true;

  /// Failed jobs from the most recent [printBatch] (for [retryFailedJobs]).
  List<ZebraJob> get lastFailedJobs =>
      List.unmodifiable(_batchRun?.failed ?? const []);

  Future<void> connect({Duration? timeout}) async {
    _setStatus(
      _status.copyWith(
        state: ZebraPrinterState.connecting,
        message: 'Connecting',
        clearError: true,
      ),
    );

    final transport = _transport ?? _createTransport();
    _transport = transport;

    try {
      await transport.connect(timeout: timeout ?? _options.connectTimeout);
      _setStatus(
        _status.copyWith(
          state: ZebraPrinterState.connected,
          message: 'Connected',
          connected: true,
          clearError: true,
        ),
      );
      _logger.call(
        ZebraLogLevel.info,
        ZebraLogScope.device,
        'Printer connected',
        printerId: id,
        data: {
          'type': descriptor.connectionType.name,
          'address': descriptor.address,
        },
      );

      if (_options.autoQueryStatusAfterConnect) {
        try {
          await queryStatus(timeout: _options.statusTimeout);
        } catch (error, stack) {
          _logger.call(
            ZebraLogLevel.warning,
            ZebraLogScope.device,
            'Post-connect status query failed',
            printerId: id,
            error: error,
            stackTrace: stack,
          );
        }
      }
    } catch (error, stack) {
      _setStatus(
        _status.copyWith(
          state: ZebraPrinterState.failed,
          message: 'Connect failed',
          connected: false,
          lastError: error,
        ),
      );
      _logger.call(
        ZebraLogLevel.error,
        ZebraLogScope.device,
        'Connect failed',
        printerId: id,
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final transport = _transport;
    _transport = null;
    await transport?.disconnect();
    _setStatus(
      _status.copyWith(
        state: ZebraPrinterState.disconnected,
        message: 'Disconnected',
        connected: false,
        readyToPrint: false,
        printing: false,
        clearHardwareStatus: true,
      ),
    );
    _logger.call(
      ZebraLogLevel.info,
      ZebraLogScope.device,
      'Printer disconnected',
      printerId: id,
    );
  }

  Future<ZebraCommandResult> printZpl(
    String zpl, {
    Duration? timeout,
  }) {
    return printRaw(zpl, timeout: timeout, language: ZebraPrinterLanguage.zpl);
  }

  Future<ZebraCommandResult> printCpcl(
    String cpcl, {
    Duration? timeout,
  }) {
    return printRaw(
      cpcl,
      timeout: timeout,
      language: ZebraPrinterLanguage.cpcl,
    );
  }

  Future<ZebraCommandResult> printRaw(
    String data, {
    Duration? timeout,
    ZebraPrinterLanguage language = ZebraPrinterLanguage.unknown,
  }) async {
    final transport = _requireTransport();
    final payload = data.trimRight();
    if (payload.isEmpty) {
      return const ZebraCommandResult(
        ok: false,
        result: 'empty',
        message: 'Print payload is empty.',
      );
    }

    _setStatus(
      _status.copyWith(
        state: ZebraPrinterState.printing,
        message: 'Printing',
        printing: true,
        clearError: true,
      ),
    );
    _logger.call(
      ZebraLogLevel.info,
      ZebraLogScope.device,
      'Printing ${language.name} (${payload.length} chars)',
      printerId: id,
      direction: ZebraMessageDirection.outbound,
      payload: payload.length > 2000 ? '${payload.substring(0, 2000)}…' : payload,
    );

    try {
      await transport.write(
        Uint8List.fromList(utf8.encode(payload.endsWith('\n') ? payload : '$payload\n')),
        timeout: timeout ?? _options.writeTimeout,
      );
      _setStatus(
        _status.copyWith(
          state: ZebraPrinterState.ready,
          message: 'Print sent',
          printing: false,
          readyToPrint: true,
          language: language,
          clearError: true,
        ),
      );
      return const ZebraCommandResult(
        ok: true,
        result: 'ok',
        message: 'Print sent.',
      );
    } catch (error, stack) {
      _setStatus(
        _status.copyWith(
          state: ZebraPrinterState.failed,
          message: 'Print failed',
          printing: false,
          lastError: error,
        ),
      );
      _logger.call(
        ZebraLogLevel.error,
        ZebraLogScope.device,
        'Print failed',
        printerId: id,
        error: error,
        stackTrace: stack,
      );
      return ZebraCommandResult(
        ok: false,
        result: 'printFailed',
        message: error.toString(),
      );
    }
  }

  Future<ZebraPrinterStatus> queryStatus({Duration? timeout}) async {
    final transport = _requireTransport();

    if (descriptor.connectionType != ZebraConnectionType.tcp) {
      final native = await MethodChannelZebraTransport.queryNativeStatus(
        printerId: id,
      );
      if (native != null) {
        final updated = ZebraStatusParser.fromNativeMap(
          native,
          printer: descriptor,
          previous: _status,
        );
        _setStatus(updated);
        return updated;
      }
    }

    await transport.write(
      ZebraSgd.hostStatusCommand(),
      timeout: timeout ?? _options.statusTimeout,
    );
    final bytes = await transport.read(
      timeout: timeout ?? _options.statusTimeout,
    );
    if (bytes == null || bytes.isEmpty) {
      final updated = _status.copyWith(
        state: ZebraPrinterState.connected,
        message: 'Status pending',
        connected: true,
        hardwareStatusLabel: 'unknown',
      );
      _setStatus(updated);
      return updated;
    }

    final raw = utf8.decode(bytes, allowMalformed: true);
    final updated = ZebraStatusParser.fromHostStatus(
      raw,
      printer: descriptor,
      previous: _status,
    );
    _setStatus(updated);
    _logger.call(
      ZebraLogLevel.debug,
      ZebraLogScope.protocol,
      'Host status: ${updated.hardwareStatusLabel}',
      printerId: id,
      direction: ZebraMessageDirection.inbound,
      payload: raw,
    );
    return updated;
  }

  Future<String?> sgdGet(String name, {Duration? timeout}) async {
    final transport = _requireTransport();
    await transport.write(
      ZebraSgd.getCommand(name),
      timeout: timeout ?? _options.statusTimeout,
    );
    final bytes = await transport.read(
      timeout: timeout ?? _options.statusTimeout,
    );
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true).trim();
  }

  Future<ZebraCommandResult> sgdSet(
    String name,
    String value, {
    Duration? timeout,
  }) async {
    final transport = _requireTransport();
    try {
      await transport.write(
        ZebraSgd.setCommand(name, value),
        timeout: timeout ?? _options.writeTimeout,
      );
      return const ZebraCommandResult(
        ok: true,
        result: 'ok',
        message: 'SGD set sent.',
      );
    } catch (error) {
      return ZebraCommandResult(
        ok: false,
        result: 'sgdSetFailed',
        message: error.toString(),
      );
    }
  }

  Future<bool> waitForReady({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await queryStatus();
        if (status.isUsable) return true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Media calibration (`~JC`).
  Future<ZebraCommandResult> calibrate({Duration? timeout}) {
    return _sendRawCommand(
      '~JC',
      timeout: timeout,
      okMessage: 'Calibrate sent.',
      failResult: 'calibrateFailed',
    );
  }

  /// Print configuration / settings label (`~WC`).
  Future<ZebraCommandResult> printConfigurationLabel({Duration? timeout}) {
    return _sendRawCommand(
      '~WC',
      timeout: timeout,
      okMessage: 'Configuration label sent.',
      failResult: 'configLabelFailed',
    );
  }

  /// Small ZPL test label. Optional [text] is rendered on the label.
  Future<ZebraCommandResult> printTestLabel({
    String? text,
    Duration? timeout,
  }) {
    final body = (text == null || text.trim().isEmpty)
        ? 'dcs_zebra test'
        : text.trim();
    final escaped = body.replaceAll('^', ' ').replaceAll('~', ' ');
    final zpl = '^XA\n'
        '^FO30,30^A0N,40,40^FD$escaped^FS\n'
        '^FO30,90^A0N,28,28^FD${descriptor.displayName}^FS\n'
        '^XZ';
    return printZpl(zpl, timeout: timeout);
  }

  /// SGD `print.tone` (darkness). Typical range depends on model (−30…30 or 0…30).
  Future<ZebraCommandResult> setDarkness(int value, {Duration? timeout}) {
    return sgdSet('print.tone', '$value', timeout: timeout);
  }

  Future<int?> getDarkness({Duration? timeout}) async {
    final raw = await sgdGet('print.tone', timeout: timeout);
    return _parseSgdInt(raw);
  }

  /// SGD `media.speed`.
  Future<ZebraCommandResult> setSpeed(int value, {Duration? timeout}) {
    return sgdSet('media.speed', '$value', timeout: timeout);
  }

  Future<int?> getSpeed({Duration? timeout}) async {
    final raw = await sgdGet('media.speed', timeout: timeout);
    return _parseSgdInt(raw);
  }

  /// SGD `power.percent_full`. Returns null on desktop models / empty replies.
  Future<int?> batteryPercent({Duration? timeout}) async {
    final raw = await sgdGet('power.percent_full', timeout: timeout);
    return _parseSgdInt(raw);
  }

  /// Prints [jobs] sequentially, yielding per-job [ZebraJobProgress].
  ///
  /// Cancel via [cancelBatch] or by cancelling the stream subscription.
  /// Failed jobs are retained for [retryFailedJobs].
  Stream<ZebraJobProgress> printBatch(
    List<ZebraJob> jobs, {
    bool waitForReady = true,
    int maxRetries = 0,
  }) {
    final run = _ZebraBatchRun(jobs: List<ZebraJob>.from(jobs));
    _batchRun = run;

    late StreamController<ZebraJobProgress> controller;
    controller = StreamController<ZebraJobProgress>(
      onListen: () {
        unawaited(_runBatch(
          run: run,
          waitForReady: waitForReady,
          maxRetries: maxRetries,
          controller: controller,
        ));
      },
      onCancel: () {
        run.cancelled = true;
      },
    );
    return controller.stream;
  }

  /// Cancels an in-flight [printBatch].
  void cancelBatch() {
    _batchRun?.cancelled = true;
  }

  /// Re-runs jobs that failed in the last [printBatch].
  Stream<ZebraJobProgress> retryFailedJobs({
    bool waitForReady = true,
    int maxRetries = 0,
  }) {
    final failed = lastFailedJobs;
    return printBatch(
      failed,
      waitForReady: waitForReady,
      maxRetries: maxRetries,
    );
  }

  Future<void> _runBatch({
    required _ZebraBatchRun run,
    required bool waitForReady,
    required int maxRetries,
    required StreamController<ZebraJobProgress> controller,
  }) async {
    final total = run.jobs.length;
    run.failed.clear();

    for (var i = 0; i < run.jobs.length; i++) {
      if (run.cancelled || controller.isClosed) break;
      final job = run.jobs[i];
      controller.add(
        ZebraJobProgress(
          jobId: job.id,
          state: ZebraJobState.queued,
          index: i,
          total: total,
        ),
      );

      if (run.cancelled) break;

      var attempt = 0;
      var succeeded = false;
      String? lastError;

      while (attempt <= maxRetries && !run.cancelled) {
        attempt++;
        controller.add(
          ZebraJobProgress(
            jobId: job.id,
            state: ZebraJobState.sending,
            index: i,
            total: total,
          ),
        );

        if (waitForReady) {
          final ready = await this.waitForReady(
            timeout: _options.statusTimeout + const Duration(seconds: 25),
          );
          if (!ready && !run.cancelled) {
            lastError = 'Printer not ready';
            if (attempt <= maxRetries) continue;
            break;
          }
        }

        if (run.cancelled) break;

        final result = await printRaw(
          job.data,
          language: job.language,
        );
        if (result.ok) {
          succeeded = true;
          controller.add(
            ZebraJobProgress(
              jobId: job.id,
              state: ZebraJobState.done,
              index: i,
              total: total,
            ),
          );
          break;
        }
        lastError = result.message ?? result.result;
        if (attempt <= maxRetries) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }

      if (!succeeded && !run.cancelled) {
        run.failed.add(job);
        controller.add(
          ZebraJobProgress(
            jobId: job.id,
            state: ZebraJobState.failed,
            index: i,
            total: total,
            error: lastError ?? 'Print failed',
          ),
        );
      }
    }

    if (!controller.isClosed) await controller.close();
  }

  Future<ZebraCommandResult> _sendRawCommand(
    String command, {
    Duration? timeout,
    required String okMessage,
    required String failResult,
  }) async {
    final transport = _requireTransport();
    final payload = command.endsWith('\n') ? command : '$command\n';
    try {
      await transport.write(
        Uint8List.fromList(utf8.encode(payload)),
        timeout: timeout ?? _options.writeTimeout,
      );
      _logger.call(
        ZebraLogLevel.info,
        ZebraLogScope.device,
        'Command sent: ${command.trim()}',
        printerId: id,
        direction: ZebraMessageDirection.outbound,
        payload: command.trim(),
      );
      return ZebraCommandResult(
        ok: true,
        result: 'ok',
        message: okMessage,
      );
    } catch (error, stack) {
      _logger.call(
        ZebraLogLevel.error,
        ZebraLogScope.device,
        'Command failed: ${command.trim()}',
        printerId: id,
        error: error,
        stackTrace: stack,
      );
      return ZebraCommandResult(
        ok: false,
        result: failResult,
        message: error.toString(),
      );
    }
  }

  static int? _parseSgdInt(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    // SGD replies may be quoted: "75" or bare 75 / 75\r\n
    final unquoted = trimmed
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();
    if (unquoted.isEmpty ||
        unquoted.toLowerCase() == 'null' ||
        unquoted == '?' ||
        unquoted.toLowerCase() == 'n/a') {
      return null;
    }
    return int.tryParse(unquoted.split(RegExp(r'\s+')).first);
  }

  ZebraTransport _createTransport() {
    switch (descriptor.connectionType) {
      case ZebraConnectionType.tcp:
        final parts = descriptor.address.split(':');
        final host = parts.first;
        final port = parts.length > 1
            ? int.tryParse(parts[1]) ?? _options.defaultTcpPort
            : _options.defaultTcpPort;
        return TcpZebraTransport(
          endpoint: ZebraEndpoint(
            host: host,
            port: port,
            statusPort: _options.defaultStatusPort,
          ),
          logger: _logger,
          printerId: id,
        );
      case ZebraConnectionType.bluetooth:
      case ZebraConnectionType.bluetoothLe:
      case ZebraConnectionType.usb:
      case ZebraConnectionType.serial:
        return MethodChannelZebraTransport(
          descriptor: descriptor,
          logger: _logger,
        );
    }
  }

  ZebraTransport _requireTransport() {
    final transport = _transport;
    if (transport == null || !transport.isConnected) {
      throw const ZebraRequestFailure('Printer is not connected.');
    }
    return transport;
  }

  void _setStatus(ZebraPrinterStatus status) {
    _status = status;
    _onStatus(status);
  }
}

class _ZebraBatchRun {
  _ZebraBatchRun({required this.jobs});

  final List<ZebraJob> jobs;
  final failed = <ZebraJob>[];
  var cancelled = false;
}
