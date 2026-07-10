import 'cupps_models.dart';

/// Hardware configure plan keyed by CUPPS device type.
class CuppsConfigurePlan {
  const CuppsConfigurePlan({
    this.boardingPassCommands = const [],
    this.bagTagCommands = const [],
    this.boardingGateCommands = const [],
  });

  final List<String> boardingPassCommands;
  final List<String> bagTagCommands;
  final List<String> boardingGateCommands;

  List<String> commandsFor(CuppsDeviceType type) {
    return switch (type) {
      CuppsDeviceType.boardingPassPrinter => boardingPassCommands,
      CuppsDeviceType.bagTagPrinter => bagTagCommands,
      CuppsDeviceType.boardingGateReader => boardingGateCommands,
      _ => const [],
    };
  }

  bool get isEmpty =>
      boardingPassCommands.isEmpty &&
      bagTagCommands.isEmpty &&
      boardingGateCommands.isEmpty;
}

/// Resolves configure command placeholders for a target airline.
class CuppsConfigureCommands {
  const CuppsConfigureCommands._();

  static const boardingPassDeviceId = 0;
  static const bagTagDeviceId = 1;
  static const boardingGateDeviceId = 2;

  static List<String> normalizeCommands(
    Iterable<String> commands, {
    required String airlineCode,
  }) {
    final airline = airlineCode.trim().toUpperCase();
    return commands
        .map((command) => _resolveAirlinePlaceholders(command, airline))
        .map((command) => command.replaceAll('\r', '').trim())
        .where((command) => command.isNotEmpty)
        .toList(growable: false);
  }

  static CuppsConfigurePlan planFromDeviceConfigs(
    Iterable<CuppsDeviceConfigEntry> configs, {
    required String airlineCode,
  }) {
    var bp = const <String>[];
    var bt = const <String>[];
    var bg = const <String>[];

    for (final config in configs) {
      final commands = normalizeCommands(config.commands, airlineCode: airlineCode);
      switch (config.deviceId) {
        case boardingPassDeviceId:
          bp = commands;
        case bagTagDeviceId:
          bt = commands;
        case boardingGateDeviceId:
          bg = commands;
      }
    }

    return CuppsConfigurePlan(
      boardingPassCommands: bp,
      bagTagCommands: bt,
      boardingGateCommands: bg,
    );
  }

  /// Defaults aligned with Abomis virtual CUPPS `PrintFiles` and bdcs init order.
  static CuppsConfigurePlan virtualPlatformDefaults({required String airlineCode}) {
    return planFromDeviceConfigs(
      [
        CuppsDeviceConfigEntry(
          deviceId: boardingPassDeviceId,
          commands: _virtualBoardingPassCommands,
        ),
        CuppsDeviceConfigEntry(
          deviceId: bagTagDeviceId,
          commands: _virtualBagTagCommands,
        ),
      ],
      airlineCode: airlineCode,
    );
  }

  static String _resolveAirlinePlaceholders(String command, String airline) {
    return command
        .replaceAll('EP#AIRLINEID=000', 'EP#AIRLINEID=$airline')
        .replaceAll('EP#AIRLINEID=999', 'EP#AIRLINEID=$airline')
        .replaceAll('{AIRLINE}', airline)
        .replaceAll('{airline}', airline);
  }

  static const _virtualBoardingPassCommands = <String>[
    'EP#AIRLINEID={AIRLINE}#HARDCODE=HDC#FONT=L',
    'PT##?G9N#@;#TICKT#CHKIN#BOARD#01011101#0205O13O57L#0317F10F54#0405H57G13L#0505H65H13L#0603F43G54L#0705F45G56L#1010B25B54#1105H43L#1205G43L#1505O45L#1808O28O65L#2205M28R#2305M44M58R#3701D05#4406M13R#4550Q15L#4605D10D54#FABRE012232#FBBRE012232#',
    'TT08#01B0230600150105000600000#02B1390600150030000600000#03S0001150006174000000#04T026066000ALL@00000SEQ:#05T135566000ALL@00000SEQ:#06T063066000ALL@00000PNR:#07T100566000ALL@00000Class:#08T032050000ALL@00000Gate:#09T072050000ALL@00000Boarding Time:#10T115050000ALL@00000Seat:#11T150050000ALL@00000Seat:#12T157037000ALL@00000To:#13T135537000ALL@00000From:#14T085032000ALL@00000Departure Time:#15T085028000ALL@00000Flight:#16T085037000ALL@00000Departure Date:#17T024023000ALL@00000Passenger Name:#18T024032000ALL@00000From:#19T024037000ALL@00000To:#20T135523000ALL@00000Passenger Name:#21T157066000ALL@00000PNR:#',
  ];

  static const _virtualBagTagCommands = <String>[
    'EP#AIRLINEID={AIRLINE}#HARDCODE=HDC#FONT=L',
    'BTT1089~H0500210=#02C0 E394250304#03B1 A385250541#04C0MI129450201#06B1 A002250541=03#11C0MA146250304=02#12B1 3150454041=03#13B1 3231454041=03#14B1 A190254041=03#22C0 E406250304=02#23B1 A397250541=03#47C0MI107450201=89#48C0M1107050303=71#49C0M1107180303=72#51C0 1042050201=85#54C0 1030050201TO:#55C1 1030100201=86#56C0 I030370201=71#57C0 I030450201=72#58C0 1022050201VIA1:#59C0 1018050201VIA2:#63C0 1038050201=89#64C0 1026050201=75#65C0 1008050201=71#66C0M1107370201=83#67C0M1122050201TO:#68C0 1012050201=02#69C0M1103050201VIA1:#70C0M1085050201VIA2:#71C0M1132050303#72C0M1132180303#73C0MI132450201#75C0 I034450201#83C0 I038450201#85C0M1129050201#86C0MA114251011#89C0MI129450201#91S0MA125250450#93S0MA106250450#94S0MA070250450#95S0MA088250450#',
  ];
}

class CuppsDeviceConfigEntry {
  const CuppsDeviceConfigEntry({
    required this.deviceId,
    required this.commands,
  });

  final int deviceId;
  final List<String> commands;
}
