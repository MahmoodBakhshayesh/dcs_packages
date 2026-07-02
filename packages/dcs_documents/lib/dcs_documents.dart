/// Document payload helpers for DCS printers and common-use devices.
library;

import 'package:dcs_common/dcs_common.dart';

enum DcsDocumentType { boardingPass, bagTag, genericAea }

class DcsDocumentPayload {
  const DcsDocumentPayload({
    required this.type,
    required this.documentId,
    required this.content,
    this.targetDevice = DcsDeviceKind.unknown,
    this.stockName = '',
    this.metadata = const {},
  });

  final DcsDocumentType type;
  final String documentId;
  final String content;
  final DcsDeviceKind targetDevice;
  final String stockName;
  final Map<String, String> metadata;

  bool get isPrintable => content.trim().isNotEmpty;
}

class BoardingPassDocument {
  const BoardingPassDocument({
    required this.passengerName,
    required this.flightNumber,
    required this.origin,
    required this.destination,
    required this.seat,
    required this.sequenceNumber,
    this.boardingGroup = '',
  });

  final String passengerName;
  final String flightNumber;
  final String origin;
  final String destination;
  final String seat;
  final String sequenceNumber;
  final String boardingGroup;

  DcsDocumentPayload toPayload({String documentId = ''}) {
    final lines = [
      'BOARDING PASS',
      passengerName,
      '$flightNumber $origin-$destination',
      'SEAT $seat SEQ $sequenceNumber',
      if (boardingGroup.isNotEmpty) 'GROUP $boardingGroup',
    ];
    return DcsDocumentPayload(
      type: DcsDocumentType.boardingPass,
      documentId: documentId,
      targetDevice: DcsDeviceKind.boardingPassPrinter,
      stockName: 'ATB',
      content: lines.join('\n'),
    );
  }
}

class BagTagDocument {
  const BagTagDocument({
    required this.tagNumber,
    required this.passengerName,
    required this.destination,
    this.weightKg,
  });

  final String tagNumber;
  final String passengerName;
  final String destination;
  final double? weightKg;

  DcsDocumentPayload toPayload() {
    final lines = [
      'BAG TAG',
      tagNumber,
      passengerName,
      'TO $destination',
      if (weightKg != null) '${weightKg!.toStringAsFixed(1)} KG',
    ];
    return DcsDocumentPayload(
      type: DcsDocumentType.bagTag,
      documentId: tagNumber,
      targetDevice: DcsDeviceKind.bagTagPrinter,
      stockName: 'BTP',
      content: lines.join('\n'),
    );
  }
}
