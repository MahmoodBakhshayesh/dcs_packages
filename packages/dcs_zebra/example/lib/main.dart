import 'dart:async';

import 'package:dcs_zebra/dcs_zebra.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ZebraExampleApp());
}

class ZebraExampleApp extends StatefulWidget {
  const ZebraExampleApp({super.key});

  @override
  State<ZebraExampleApp> createState() => _ZebraExampleAppState();
}

class _ZebraExampleAppState extends State<ZebraExampleApp> {
  final _hostController = TextEditingController(text: '192.168.1.50');
  final _client = ZebraClient();
  final _discovered = <ZebraPrinterDescriptor>[];
  final _batchProgress = <String>[];

  String _log = '';
  ZebraPrinter? _printer;
  ZebraPermissionState? _permission;
  StreamSubscription<ZebraPrinterDescriptor>? _discoverSub;
  StreamSubscription<ZebraJobProgress>? _batchSub;
  var _discovering = false;

  @override
  void dispose() {
    _discoverSub?.cancel();
    _batchSub?.cancel();
    _hostController.dispose();
    _client.dispose();
    super.dispose();
  }

  void _append(String line) {
    setState(() => _log = '${DateTime.now().toIso8601String()} $line\n$_log');
  }

  Future<void> _ensurePermissions() async {
    final state = await _client.ensureBluetoothPermissions();
    setState(() => _permission = state);
    _append('Permissions: ${state.name}');
  }

  Future<void> _discover() async {
    await _discoverSub?.cancel();
    setState(() {
      _discovered.clear();
      _discovering = true;
    });
    _append('Discovery started…');
    _discoverSub = _client
        .discoverStream(
      types: const [
        ZebraConnectionType.bluetooth,
        ZebraConnectionType.bluetoothLe,
        ZebraConnectionType.tcp,
      ],
      timeout: const Duration(seconds: 8),
    )
        .listen(
      (printer) {
        setState(() {
          final index = _discovered.indexWhere((d) => d.id == printer.id);
          if (index >= 0) {
            _discovered[index] = printer;
          } else {
            _discovered.add(printer);
          }
        });
        _append(
          'Found ${printer.displayName} rssi=${printer.rssi} '
          'paired=${printer.paired} mobile=${printer.isMobileModel}',
        );
      },
      onDone: () {
        setState(() => _discovering = false);
        _append('Discovery finished (${_discovered.length})');
      },
      onError: (Object e) {
        setState(() => _discovering = false);
        _append('Discovery error: $e');
      },
    );
  }

  Future<void> _pair(ZebraPrinterDescriptor descriptor) async {
    final result = await _client.pair(descriptor);
    _append('Pair ${descriptor.displayName}: ${result.name}');
    if (result == ZebraPairingResult.openSystemSettings && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'iOS: pair the Zebra printer in Settings → Bluetooth, '
            'then return to the app.',
          ),
        ),
      );
    }
  }

  Future<void> _connectTcp() async {
    try {
      _printer = await _client.connectTcp(
        host: _hostController.text.trim(),
        role: ZebraPrinterRole.boardingPass,
      );
      _append('Connected TCP: ${_printer!.id}');
      setState(() {});
    } catch (e) {
      _append('Connect failed: $e');
    }
  }

  Future<void> _connectDescriptor(ZebraPrinterDescriptor descriptor) async {
    try {
      _printer = await _client.connectDescriptor(
        descriptor.copyWith(role: ZebraPrinterRole.boardingPass),
      );
      _append('Connected: ${_printer!.id}');
      setState(() {});
    } catch (e) {
      _append('Connect failed: $e');
    }
  }

  Future<void> _status() async {
    final printer = _printer;
    if (printer == null) return;
    try {
      final status = await printer.queryStatus();
      final battery = await printer.batteryPercent();
      _append(
        'Status: ${status.hardwareStatusLabel} ready=${status.readyToPrint} '
        'battery=${battery ?? "n/a"}%',
      );
      setState(() {});
    } catch (e) {
      _append('Status failed: $e');
    }
  }

  Future<void> _testPrint() async {
    final printer = _printer;
    if (printer == null) return;
    final result = await printer.printTestLabel(text: 'DCS MobileViews');
    _append(result.ok ? 'Test print OK' : 'Test print failed: ${result.message}');
  }

  Future<void> _calibrate() async {
    final printer = _printer;
    if (printer == null) return;
    final result = await printer.calibrate();
    _append(result.ok ? 'Calibrate OK' : 'Calibrate failed: ${result.message}');
  }

  Future<void> _printBatch() async {
    final printer = _printer;
    if (printer == null) return;
    await _batchSub?.cancel();
    setState(() => _batchProgress.clear());
    final jobs = List.generate(
      3,
      (i) => ZebraJob(
        id: 'job-$i',
        data: '^XA^FO40,40^A0N,40,40^FDBatch ${i + 1}^FS^XZ',
      ),
    );
    _batchSub = printer.printBatch(jobs, waitForReady: false).listen(
      (event) {
        setState(() {
          _batchProgress.insert(
            0,
            '${event.jobId} ${event.state.name}'
            '${event.error != null ? " (${event.error})" : ""}',
          );
        });
      },
      onDone: () => _append('Batch complete'),
      onError: (Object e) => _append('Batch error: $e'),
    );
  }

  void _cancelBatch() {
    _printer?.cancelBatch();
    _append('Batch cancel requested');
  }

  Future<void> _retryBatch() async {
    final printer = _printer;
    if (printer == null || printer.lastFailedJobs.isEmpty) {
      _append('No failed jobs to retry');
      return;
    }
    await _batchSub?.cancel();
    _batchSub = printer.retryFailedJobs(waitForReady: false).listen(
      (event) {
        setState(() {
          _batchProgress.insert(
            0,
            'retry ${event.jobId} ${event.state.name}',
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _printer?.status;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('dcs_zebra example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(labelText: 'Printer host'),
              ),
              const SizedBox(height: 8),
              Text(
                'BT permission: ${_permission?.name ?? "not checked"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _ensurePermissions,
                    child: const Text('Permissions'),
                  ),
                  FilledButton(
                    onPressed: _discovering ? null : _discover,
                    child: Text(_discovering ? 'Discovering…' : 'Discover'),
                  ),
                  FilledButton(onPressed: _connectTcp, child: const Text('Connect TCP')),
                  FilledButton(onPressed: _status, child: const Text('Status')),
                  FilledButton(onPressed: _testPrint, child: const Text('Test print')),
                  FilledButton(onPressed: _calibrate, child: const Text('Calibrate')),
                  FilledButton(onPressed: _printBatch, child: const Text('Batch')),
                  OutlinedButton(onPressed: _cancelBatch, child: const Text('Cancel batch')),
                  OutlinedButton(onPressed: _retryBatch, child: const Text('Retry failed')),
                ],
              ),
              const SizedBox(height: 12),
              if (status != null)
                Row(
                  children: [
                    Image.asset(
                      ZebraStatusAssets.forPrinterStatus(status),
                      package: ZebraStatusAssets.package,
                      width: 48,
                      height: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(status.message)),
                  ],
                ),
              const SizedBox(height: 8),
              Text('Discovered', style: Theme.of(context).textTheme.titleSmall),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  itemCount: _discovered.length,
                  itemBuilder: (context, index) {
                    final d = _discovered[index];
                    final rssi = d.rssi == null ? '—' : '${d.rssi} dBm';
                    return ListTile(
                      dense: true,
                      title: Text(d.displayName),
                      subtitle: Text(
                        '${d.connectionType.name}  rssi=$rssi  '
                        'paired=${d.paired}  mobile=${d.isMobileModel}',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => _pair(d),
                            child: const Text('Pair'),
                          ),
                          TextButton(
                            onPressed: () => _connectDescriptor(d),
                            child: const Text('Connect'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_batchProgress.isNotEmpty) ...[
                Text('Batch', style: Theme.of(context).textTheme.titleSmall),
                SizedBox(
                  height: 72,
                  child: ListView(
                    children: _batchProgress.map(Text.new).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(child: SingleChildScrollView(child: Text(_log))),
            ],
          ),
        ),
      ),
    );
  }
}
