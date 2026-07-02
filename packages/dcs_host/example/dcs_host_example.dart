import 'package:dcs_common/dcs_common.dart';
import 'package:dcs_host/dcs_host.dart';

void main() async {
  final client = DcsHostClient(_ExampleHostAdapter());
  final response = await client.send(
    const DcsHostRequest(
      id: 'example',
      type: DcsHostMessageType.freeText,
      payload: 'PING',
    ),
  );
  print(response.payload);
}

class _ExampleHostAdapter implements DcsHostAdapter {
  @override
  DcsTransportKind get transport => DcsTransportKind.hostApi;

  @override
  Future<DcsHostResponse> send(DcsHostRequest request) async {
    return DcsHostResponse(requestId: request.id, ok: true, payload: 'PONG');
  }
}
