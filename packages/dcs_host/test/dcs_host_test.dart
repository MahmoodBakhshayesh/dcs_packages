import 'package:dcs_common/dcs_common.dart';
import 'package:dcs_host/dcs_host.dart';
import 'package:test/test.dart';

void main() {
  group('host client', () {
    test('sends through adapter', () async {
      final client = DcsHostClient(_FakeHostAdapter());
      final response = await client.send(
        const DcsHostRequest(
          id: '1',
          type: DcsHostMessageType.freeText,
          payload: 'PING',
        ),
      );

      expect(response.ok, isTrue);
      expect(response.payload, 'PONG');
    });

    test('rejects empty payload', () {
      final client = DcsHostClient(_FakeHostAdapter());
      expect(
        () => client.send(
          const DcsHostRequest(
            id: '1',
            type: DcsHostMessageType.freeText,
            payload: '',
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}

class _FakeHostAdapter implements DcsHostAdapter {
  @override
  DcsTransportKind get transport => DcsTransportKind.hostApi;

  @override
  Future<DcsHostResponse> send(DcsHostRequest request) async {
    return DcsHostResponse(requestId: request.id, ok: true, payload: 'PONG');
  }
}
