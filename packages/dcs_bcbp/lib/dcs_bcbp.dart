/// Minimal IATA BCBP parsing helpers.
library;

class BcbpParseException implements Exception {
  const BcbpParseException(this.message);

  final String message;

  @override
  String toString() => 'BcbpParseException: $message';
}

class BcbpPassengerName {
  const BcbpPassengerName({required this.raw});

  final String raw;

  String get surname => raw.split('/').first.trim();

  String get givenNames {
    final parts = raw.split('/');
    if (parts.length < 2) return '';
    return parts.skip(1).join('/').trim();
  }
}

class BcbpLeg {
  const BcbpLeg({
    required this.operatingCarrier,
    required this.flightNumber,
    required this.origin,
    required this.destination,
    required this.julianDate,
    required this.compartment,
    required this.seat,
    required this.sequenceNumber,
  });

  final String operatingCarrier;
  final String flightNumber;
  final String origin;
  final String destination;
  final String julianDate;
  final String compartment;
  final String seat;
  final String sequenceNumber;
}

class BcbpData {
  const BcbpData({
    required this.formatCode,
    required this.numberOfLegs,
    required this.passengerName,
    required this.electronicTicketIndicator,
    required this.legs,
    required this.raw,
  });

  final String formatCode;
  final int numberOfLegs;
  final BcbpPassengerName passengerName;
  final String electronicTicketIndicator;
  final List<BcbpLeg> legs;
  final String raw;

  static BcbpData parse(String value) {
    final raw = value;
    if (raw.length < 60) {
      throw const BcbpParseException('BCBP payload is too short.');
    }
    if (raw[0] != 'M') {
      throw const BcbpParseException('Only mandatory multi-leg BCBP format is supported.');
    }

    final legs = int.tryParse(raw[1]);
    if (legs == null || legs < 1) {
      throw const BcbpParseException('Invalid number of legs.');
    }

    final passengerName = raw.substring(2, 22).trim();
    final electronicTicketIndicator = raw.substring(22, 23);
    final firstLeg = raw.substring(23);

    return BcbpData(
      formatCode: raw[0],
      numberOfLegs: legs,
      passengerName: BcbpPassengerName(raw: passengerName),
      electronicTicketIndicator: electronicTicketIndicator,
      legs: [_parseLeg(firstLeg)],
      raw: raw,
    );
  }

  static BcbpLeg _parseLeg(String leg) {
    if (leg.length < 35) {
      throw const BcbpParseException('BCBP leg data is too short.');
    }
    return BcbpLeg(
      origin: leg.substring(7, 10).trim(),
      destination: leg.substring(10, 13).trim(),
      operatingCarrier: leg.substring(13, 16).trim(),
      flightNumber: leg.substring(16, 21).trim(),
      julianDate: leg.substring(21, 24).trim(),
      compartment: leg.substring(24, 25).trim(),
      seat: leg.substring(25, 29).trim(),
      sequenceNumber: leg.substring(29, 34).trim(),
    );
  }
}
