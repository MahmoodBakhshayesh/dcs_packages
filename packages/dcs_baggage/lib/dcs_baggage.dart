/// Baggage domain helpers for DCS applications.
library;

enum BaggageMessageType { bsm, bpm, brs, unknown }

class BaggageTag {
  const BaggageTag({
    required this.airlineNumericCode,
    required this.serialNumber,
  });

  final String airlineNumericCode;
  final String serialNumber;

  String get value => '$airlineNumericCode$serialNumber';

  bool get isValid =>
      RegExp(r'^\d{3}$').hasMatch(airlineNumericCode) &&
      RegExp(r'^\d{6}$').hasMatch(serialNumber);
}

class CheckedBag {
  const CheckedBag({
    required this.tag,
    required this.destination,
    this.weightKg,
    this.pieceNumber = 1,
    this.rush = false,
  });

  final BaggageTag tag;
  final String destination;
  final double? weightKg;
  final int pieceNumber;
  final bool rush;
}

class BaggageServiceMessage {
  const BaggageServiceMessage({
    required this.type,
    required this.flightNumber,
    required this.origin,
    required this.bags,
    this.passengerName = '',
  });

  final BaggageMessageType type;
  final String flightNumber;
  final String origin;
  final String passengerName;
  final List<CheckedBag> bags;

  bool get isComplete =>
      flightNumber.trim().isNotEmpty &&
      origin.trim().length == 3 &&
      bags.isNotEmpty &&
      bags.every((bag) => bag.tag.isValid && bag.destination.length == 3);
}
