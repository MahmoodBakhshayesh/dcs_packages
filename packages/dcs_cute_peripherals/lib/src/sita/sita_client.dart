import '../cute_peripheral.dart';
import '../models.dart';
import 'sita_device.dart';

class SitaClient {
  SitaClient({this.airlineCode = ''});

  final String airlineCode;
  final Map<String, SitaDevice> _devices = {};

  CutePeripheral device({
    required CutePeripheralKind kind,
    required String name,
  }) {
    return _devices.putIfAbsent(
      name,
      () => SitaDevice(
        identity: CutePeripheralIdentity(
          kind: kind,
          name: name,
          airlineCode: airlineCode,
        ),
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
