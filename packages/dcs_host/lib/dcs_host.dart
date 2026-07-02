/// Host messaging contracts for DCS integrations.
library;

import 'package:dcs_common/dcs_common.dart';

enum DcsHostMessageType {
  availability,
  checkIn,
  seatMap,
  boarding,
  baggage,
  freeText,
}

class DcsHostRequest {
  const DcsHostRequest({
    required this.id,
    required this.type,
    required this.payload,
    this.timeout = const Duration(seconds: 20),
    this.metadata = const {},
  });

  final String id;
  final DcsHostMessageType type;
  final String payload;
  final Duration timeout;
  final Map<String, String> metadata;
}

class DcsHostResponse {
  const DcsHostResponse({
    required this.requestId,
    required this.ok,
    required this.payload,
    this.code = '',
    this.message = '',
  });

  final String requestId;
  final bool ok;
  final String payload;
  final String code;
  final String message;
}

abstract interface class DcsHostAdapter {
  DcsTransportKind get transport;

  Future<DcsHostResponse> send(DcsHostRequest request);
}

class DcsHostClient {
  const DcsHostClient(this.adapter);

  final DcsHostAdapter adapter;

  Future<DcsHostResponse> send(DcsHostRequest request) {
    if (request.payload.trim().isEmpty) {
      throw ArgumentError.value(request.payload, 'payload', 'Payload cannot be empty.');
    }
    return adapter.send(request).timeout(request.timeout);
  }
}
