/// Item catalog (SPEC §1.6 / §2.5) merged with DCS field-key names.
library;

enum PectabCatalogGroup { passenger, flight, legs2, legs3, titles, barcode, freeText, logo, template, other }

final class PectabCatalogEntry {
  const PectabCatalogEntry({
    required this.itemNo,
    required this.label,
    this.maxLength,
    this.sample = '',
    this.dcsKey,
    this.group = PectabCatalogGroup.other,
  });

  final String itemNo;
  final String label;
  final int? maxLength;
  final String sample;

  /// Matching key from `pectab_field_keys.dart` when known.
  final String? dcsKey;
  final PectabCatalogGroup group;
}

abstract final class PectabCatalog {
  static const List<PectabCatalogEntry> bp = [
    // Data items (SPEC §1.6)
    PectabCatalogEntry(itemNo: '02', label: 'secNo (inactive)', maxLength: 5, group: PectabCatalogGroup.other),
    PectabCatalogEntry(
      itemNo: '03',
      label: 'name',
      maxLength: 30,
      sample: 'DOE/JOHN',
      dcsKey: 'Name',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '04',
      label: 'origin',
      maxLength: 15,
      sample: 'VANCOUVER',
      dcsKey: 'FromCity',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '05',
      label: 'destination',
      maxLength: 15,
      sample: 'TORONTO',
      dcsKey: 'ToCity',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '06',
      label: 'alCode',
      maxLength: 3,
      sample: 'ZZ',
      dcsKey: 'AirlineCode',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '07',
      label: 'flightNo',
      maxLength: 5,
      sample: '1200',
      dcsKey: 'FlightNumber',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(itemNo: '08', label: 'name', maxLength: 16, dcsKey: 'Name', group: PectabCatalogGroup.passenger),
    PectabCatalogEntry(
      itemNo: '09',
      label: 'alcode',
      maxLength: 3,
      dcsKey: 'AirlineCode',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '10',
      label: 'flightclass',
      maxLength: 10,
      dcsKey: 'ClassType',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '11',
      label: 'departuredate',
      maxLength: 5,
      dcsKey: 'FlightDate',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '12',
      label: 'departure_time',
      maxLength: 5,
      dcsKey: 'STD',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '13',
      label: 'origin',
      maxLength: 15,
      dcsKey: 'FromCity',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '14',
      label: 'destination',
      maxLength: 15,
      dcsKey: 'ToCity',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '15',
      label: 'unknownCode1',
      maxLength: 5,
      dcsKey: 'Class',
      group: PectabCatalogGroup.other,
    ),
    PectabCatalogEntry(
      itemNo: '16',
      label: 'flightclass',
      maxLength: 10,
      dcsKey: 'ClassType',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '17',
      label: 'departuredate',
      maxLength: 5,
      dcsKey: 'FlightDate',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '18',
      label: 'pnr',
      maxLength: 8,
      dcsKey: 'ReferenceNo',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(itemNo: '19', label: 'SSR', maxLength: 10, dcsKey: 'SSRs', group: PectabCatalogGroup.passenger),
    PectabCatalogEntry(
      itemNo: '20',
      label: 'EXTRA SEAT',
      maxLength: 5,
      dcsKey: 'ExtraSeat',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(itemNo: '21', label: 'unKnownCode2', maxLength: 4, group: PectabCatalogGroup.other),
    PectabCatalogEntry(
      itemNo: '22',
      label: 'boardingTime',
      maxLength: 5,
      dcsKey: 'BTD',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '23',
      label: 'seatNo1',
      maxLength: 5,
      sample: '12A',
      dcsKey: 'Seat',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '24',
      label: 'seatNo2',
      maxLength: 5,
      dcsKey: 'Seat',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '26',
      label: 'secNo',
      maxLength: 5,
      dcsKey: 'BaggageCount',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '27',
      label: 'tktNo',
      maxLength: 15,
      dcsKey: 'TicketNumber',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '28',
      label: 'tktNo',
      maxLength: 13,
      dcsKey: 'TicketNumber',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(itemNo: '29', label: 'ZONE', maxLength: 2, dcsKey: 'Zone', group: PectabCatalogGroup.passenger),
    PectabCatalogEntry(
      itemNo: '30',
      label: 'pcs',
      maxLength: 4,
      dcsKey: 'BaggageCount',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '31',
      label: 'W (weight)',
      maxLength: 3,
      dcsKey: 'BaggageWeight',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '32',
      label: 'Origin FULL',
      maxLength: 10,
      dcsKey: 'FromAirportName',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '33',
      label: 'Destination FULL',
      maxLength: 10,
      dcsKey: 'ToAirportName',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '34',
      label: 'flightNo',
      maxLength: 5,
      dcsKey: 'FlightNumber',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '35',
      label: 'Airline Name',
      maxLength: 15,
      dcsKey: 'AirlineName',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(itemNo: '36', label: 'logoNo', group: PectabCatalogGroup.logo),
    PectabCatalogEntry(itemNo: '37', label: 'TEMPLATE', group: PectabCatalogGroup.template),
    PectabCatalogEntry(
      itemNo: '38',
      label: 'FQTV CODE',
      maxLength: 10,
      dcsKey: 'FQTVCode',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '41',
      label: 'AGENT CODE',
      maxLength: 5,
      dcsKey: 'Agent',
      group: PectabCatalogGroup.other,
    ),
    PectabCatalogEntry(
      itemNo: '43',
      label: 'EXCESS',
      maxLength: 4,
      dcsKey: 'ExcessBaggage',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(itemNo: '44', label: 'gate', maxLength: 10, dcsKey: 'Gate', group: PectabCatalogGroup.flight),
    PectabCatalogEntry(
      itemNo: '45',
      label: 'ALLOW',
      maxLength: 10,
      dcsKey: 'WeightAllowace',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(itemNo: '46', label: 'LOGO 2', group: PectabCatalogGroup.logo),
    PectabCatalogEntry(
      itemNo: '47',
      label: 'RATE & National ID',
      maxLength: 10,
      dcsKey: 'ExcessBaggageRate',
      group: PectabCatalogGroup.other,
    ),
    PectabCatalogEntry(itemNo: 'FA', label: 'Barcode', dcsKey: 'BarcodeData', group: PectabCatalogGroup.barcode),
    PectabCatalogEntry(itemNo: 'FB', label: 'Barcode', dcsKey: 'BarcodeData', group: PectabCatalogGroup.barcode),
    // Title items
    PectabCatalogEntry(itemNo: '50', label: 'PASSENGER', maxLength: 11, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '51', label: 'FROM', maxLength: 5, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '52', label: 'TO', maxLength: 3, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '53', label: 'SEAT', maxLength: 5, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '54', label: 'GATE', maxLength: 5, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '55', label: 'SEQ', maxLength: 4, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '56', label: 'PCS', maxLength: 4, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '57', label: 'WT', maxLength: 3, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '58', label: 'NO SMOKING', maxLength: 16, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '59', label: 'CLASS', maxLength: 7, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '60', label: 'DATE', maxLength: 5, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '61', label: 'TIME', maxLength: 5, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '62', label: 'FLIGHT NO', maxLength: 13, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '63', label: 'TKNO', maxLength: 7, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '65', label: 'PNR', maxLength: 4, group: PectabCatalogGroup.titles),
    PectabCatalogEntry(itemNo: '66', label: 'BOARDING PASS', maxLength: 20, group: PectabCatalogGroup.titles),
  ];

  static const List<PectabCatalogEntry> bt = [
    PectabCatalogEntry(
      itemNo: '02',
      label: 'tag number',
      maxLength: 10,
      sample: '0000109681',
      dcsKey: 'TagNumber',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '03',
      label: 'tag number (barcode)',
      maxLength: 10,
      dcsKey: 'TagNumber',
      group: PectabCatalogGroup.barcode,
    ),
    PectabCatalogEntry(itemNo: '04', label: '= 89', maxLength: 3, group: PectabCatalogGroup.other),
    PectabCatalogEntry(
      itemNo: '71',
      label: 'airline code',
      maxLength: 3,
      dcsKey: 'LastArilineCode',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '72',
      label: 'flight no.',
      maxLength: 5,
      dcsKey: 'LastFlightNumber',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '73',
      label: 'flight date',
      maxLength: 10,
      dcsKey: 'LastFlightDate',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(itemNo: '74', label: 'origin full name', maxLength: 10, group: PectabCatalogGroup.flight),
    PectabCatalogEntry(
      itemNo: '75',
      label: 'origin 3-letter',
      maxLength: 3,
      dcsKey: 'FirstAirportCode',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '81',
      label: 'pieces / weight',
      maxLength: 7,
      dcsKey: 'BaggageCount',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '83',
      label: 'class',
      maxLength: 2,
      dcsKey: 'Lastclass',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(
      itemNo: '85',
      label: 'passenger name',
      maxLength: 15,
      sample: 'JACOB MARINO',
      dcsKey: 'Name',
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(
      itemNo: '86',
      label: 'destination 3-letter',
      maxLength: 3,
      dcsKey: 'LastAirportCode',
      group: PectabCatalogGroup.flight,
    ),
    PectabCatalogEntry(itemNo: '87', label: 'logo', group: PectabCatalogGroup.logo),
    PectabCatalogEntry(
      itemNo: '89',
      label: 'security (sequence) no.',
      maxLength: 3,
      group: PectabCatalogGroup.passenger,
    ),
    PectabCatalogEntry(itemNo: 'EA', label: 'airline full name', maxLength: 15, group: PectabCatalogGroup.flight),
    PectabCatalogEntry(itemNo: 'EB', label: 'free text 1', maxLength: 15, group: PectabCatalogGroup.freeText),
    PectabCatalogEntry(itemNo: 'EC', label: 'free text 2', maxLength: 15, group: PectabCatalogGroup.freeText),
    PectabCatalogEntry(itemNo: 'ED', label: 'free text on black', maxLength: 15, group: PectabCatalogGroup.freeText),
    PectabCatalogEntry(itemNo: 'EE', label: 'destination full name', maxLength: 15, group: PectabCatalogGroup.flight),
    PectabCatalogEntry(itemNo: 'F0', label: 'PNR', maxLength: 15, group: PectabCatalogGroup.passenger),
    PectabCatalogEntry(itemNo: 'F1', label: 'printer datetime', maxLength: 20, group: PectabCatalogGroup.other),
    PectabCatalogEntry(itemNo: 'F2', label: 'user ID', maxLength: 5, group: PectabCatalogGroup.other),
    PectabCatalogEntry(itemNo: 'F6', label: '6-digit security no.', maxLength: 6, group: PectabCatalogGroup.passenger),
    // Second leg
    PectabCatalogEntry(
      itemNo: 'E0',
      label: 'leg2 flight no',
      maxLength: 3,
      dcsKey: 'Via1AirportCode',
      group: PectabCatalogGroup.legs2,
    ),
    PectabCatalogEntry(
      itemNo: 'E1',
      label: 'leg2 city',
      maxLength: 3,
      dcsKey: 'Via1ArilineCode',
      group: PectabCatalogGroup.legs2,
    ),
    PectabCatalogEntry(
      itemNo: 'E2',
      label: 'leg2 airline',
      maxLength: 3,
      dcsKey: 'Via1FlightNumber',
      group: PectabCatalogGroup.legs2,
    ),
    PectabCatalogEntry(itemNo: 'E6', label: 'leg2 date', maxLength: 10, group: PectabCatalogGroup.legs2),
    PectabCatalogEntry(itemNo: 'E8', label: 'leg2 class', maxLength: 2, group: PectabCatalogGroup.legs2),
    PectabCatalogEntry(itemNo: 'EF', label: 'leg2 destination full', maxLength: 15, group: PectabCatalogGroup.legs2),
    PectabCatalogEntry(itemNo: 'F3', label: 'leg2 security no', maxLength: 3, group: PectabCatalogGroup.legs2),
    // Third leg
    PectabCatalogEntry(itemNo: 'E3', label: 'leg3 flight no', maxLength: 5, group: PectabCatalogGroup.legs3),
    PectabCatalogEntry(itemNo: 'E4', label: 'leg3 city', maxLength: 3, group: PectabCatalogGroup.legs3),
    PectabCatalogEntry(itemNo: 'E5', label: 'leg3 airline', maxLength: 3, group: PectabCatalogGroup.legs3),
    PectabCatalogEntry(itemNo: 'E7', label: 'leg3 date', maxLength: 10, group: PectabCatalogGroup.legs3),
    PectabCatalogEntry(itemNo: 'E9', label: 'leg3 class', maxLength: 2, group: PectabCatalogGroup.legs3),
    PectabCatalogEntry(itemNo: 'F4', label: 'leg3 destination full', maxLength: 15, group: PectabCatalogGroup.legs3),
    PectabCatalogEntry(itemNo: 'F5', label: 'leg3 security no', maxLength: 3, group: PectabCatalogGroup.legs3),
  ];

  static PectabCatalogEntry? bpByItem(String itemNo) {
    final n = itemNo.toUpperCase();
    for (final e in bp) {
      if (e.itemNo == n) return e;
    }
    return null;
  }

  static PectabCatalogEntry? btByItem(String itemNo) {
    final n = itemNo.toUpperCase();
    for (final e in bt) {
      if (e.itemNo == n) return e;
    }
    return null;
  }
}
