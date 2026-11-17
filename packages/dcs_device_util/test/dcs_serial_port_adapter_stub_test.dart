// The web build exports this stub instead of the libserialport adapter (no `dart:ffi` there).
import 'package:dcs_device_util/dcs_device_util.dart' hide DcsSerialPortAdapter;
import 'package:dcs_device_util/src/dcs_serial_port_adapter_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stub serial adapter finds no ports and refuses to connect', () async {
    const adapter = DcsSerialPortAdapter();
    expect(adapter.transport, DcsDeviceTransport.serial);
    expect(await adapter.discover(), isEmpty);

    final profile = DcsDeviceProfile(
      id: 'bc',
      label: 'Barcode Reader',
      role: DcsDeviceRole.barcodeReader,
      enabled: true,
      matcher: const DcsDeviceMatcher(portName: 'COM7'),
    );
    const device = DcsDiscoveredDevice(
      id: 'serial:COM7',
      portName: 'COM7',
      transport: DcsDeviceTransport.serial,
    );
    await expectLater(
      adapter.connect(profile, device),
      throwsA(isA<DcsDeviceConnectionException>()),
    );
  });
}
