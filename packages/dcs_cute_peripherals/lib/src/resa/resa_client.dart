import '../cute_peripheral.dart';
import '../models.dart';
import 'resa_device.dart';

class ResaClient {
  ResaClient({this.trace = false});

  final bool trace;
  final Map<String, ResaDevice> _devices = {};

  CutePeripheral device({
    required CutePeripheralKind kind,
    String? name,
    int order = 0,
  }) {
    final key = '${name ?? kind.name}#$order';
    return _devices.putIfAbsent(
      key,
      () => ResaDevice(
        identity: CutePeripheralIdentity(
          kind: kind,
          name: name ?? kind.name.toUpperCase(),
          order: order,
        ),
        trace: trace,
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
