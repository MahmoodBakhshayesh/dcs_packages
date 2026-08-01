import '../cute_peripheral.dart';
import '../models.dart';
import 'arinc_device.dart';

/// Convenience manager for multiple ARINC MUSE devices on one host.
class ArincClient {
  ArincClient({
    required this.endpoint,
    this.aeaContext = 'm/A,001',
  });

  final CutePeripheralEndpoint endpoint;
  final String aeaContext;
  final Map<String, ArincDevice> _devices = {};

  CutePeripheral device({
    required CutePeripheralKind kind,
    String? name,
  }) {
    final key = name ?? kind.name.toUpperCase();
    return _devices.putIfAbsent(
      key,
      () => ArincDevice(
        kind: kind,
        endpoint: endpoint,
        name: key,
        aeaContext: aeaContext,
      ),
    );
  }

  Future<void> closeAll() async {
    for (final device in _devices.values) {
      await device.close();
    }
  }

  Future<void> dispose() async {
    for (final device in _devices.values) {
      await device.dispose();
    }
    _devices.clear();
  }
}
