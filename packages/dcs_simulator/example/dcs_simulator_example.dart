import 'package:dcs_host/dcs_host.dart';
import 'package:dcs_simulator/dcs_simulator.dart';

void main() async {
  final adapter = SimulatedHostAdapter(
    responses: const {DcsHostMessageType.freeText: 'SIM OK'},
  );
  final response = await adapter.send(
    const DcsHostRequest(
      id: 'example',
      type: DcsHostMessageType.freeText,
      payload: 'PING',
    ),
  );
  print(response.payload);
}
