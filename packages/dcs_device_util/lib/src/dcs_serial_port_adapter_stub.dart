// Serial adapter for platforms without `dart:ffi` (web). `dcs_adapters.dart` exports
// `dcs_serial_port_adapter_ffi.dart` everywhere else. Discovery finds no ports and connect fails with a
// clear [DcsDeviceConnectionException], so the controller reports the device as unavailable.
import 'dcs_adapters.dart';
import 'dcs_models.dart';

/// Serial adapter stand-in where libserialport cannot load (web): no ports, never connects.
class DcsSerialPortAdapter implements DcsDeviceAdapter {
  const DcsSerialPortAdapter();

  @override
  DcsDeviceTransport get transport => DcsDeviceTransport.serial;

  @override
  Future<List<DcsDiscoveredDevice>> discover() async => const [];

  @override
  Future<DcsDeviceSession> connect(
    DcsDeviceProfile profile,
    DcsDiscoveredDevice device,
  ) async {
    throw DcsDeviceConnectionException(
      'Serial port ${device.portName} is not available on this platform: serial ports need the desktop app.',
    );
  }
}
