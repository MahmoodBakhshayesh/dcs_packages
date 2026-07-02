import 'package:dcs_common/dcs_common.dart';
import 'package:dcs_host/dcs_host.dart';
import 'package:dcs_simulator/dcs_simulator.dart';
import 'package:test/test.dart';

void main() {
  group('simulator', () {
    test('updates simulated device state', () {
      final device = SimulatedDcsDevice(
        component: const DcsRuntimeComponent(
          id: 'reader',
          label: 'Reader',
          module: DcsPackageModule.simulator,
        ),
      );

      device.setState(DcsRuntimeState.connected, 'Connected');

      expect(device.status.state, DcsRuntimeState.connected);
    });

    test('returns simulated host response', () async {
      final adapter = SimulatedHostAdapter(
        responses: const {DcsHostMessageType.freeText: 'OK'},
      );
      final response = await adapter.send(
        const DcsHostRequest(
          id: '1',
          type: DcsHostMessageType.freeText,
          payload: 'PING',
        ),
      );

      expect(response.payload, 'OK');
      expect(response.ok, isTrue);
    });
  });
}
