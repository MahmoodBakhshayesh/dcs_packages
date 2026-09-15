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
  String _log = '';
  ZebraPrinter? _printer;

  @override
  void dispose() {
    _hostController.dispose();
    _client.dispose();
    super.dispose();
  }

  void _append(String line) {
    setState(() => _log = '${DateTime.now().toIso8601String()} $line\n$_log');
  }

  Future<void> _connect() async {
    try {
      _printer = await _client.connectTcp(
        host: _hostController.text.trim(),
        role: ZebraPrinterRole.boardingPass,
      );
      _append('Connected: ${_printer!.id}');
    } catch (e) {
      _append('Connect failed: $e');
    }
  }

  Future<void> _status() async {
    final printer = _printer;
    if (printer == null) return;
    try {
      final status = await printer.queryStatus();
      _append('Status: ${status.hardwareStatusLabel} ready=${status.readyToPrint}');
    } catch (e) {
      _append('Status failed: $e');
    }
  }

  Future<void> _print() async {
    final printer = _printer;
    if (printer == null) return;
    const zpl = '^XA^FO50,50^A0N,40,40^FDdcs_zebra example^FS^XZ';
    final result = await printer.printZpl(zpl);
    _append(result.ok ? 'Print OK' : 'Print failed: ${result.message}');
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(onPressed: _connect, child: const Text('Connect TCP')),
                  FilledButton(onPressed: _status, child: const Text('Status')),
                  FilledButton(onPressed: _print, child: const Text('Print ZPL')),
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
                    Text(status.message),
                  ],
                ),
              const SizedBox(height: 12),
              Expanded(child: SingleChildScrollView(child: Text(_log))),
            ],
          ),
        ),
      ),
    );
  }
}
