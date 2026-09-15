import 'zebra_models.dart';

enum ZebraDeviceVisualStatus {
  natural('natural'),
  active('active'),
  disconnect('disconnect'),
  initializing('in'),
  locked('locked'),
  dataAvailable('data_available'),
  printing('printing'),
  configuring('configuring'),
  inUse('inuse'),
  jammed('jammed'),
  open('open'),
  paperOut('paper_out'),
  failed('failed');

  const ZebraDeviceVisualStatus(this.fileSuffix);

  final String fileSuffix;
}

class ZebraStatusAssets {
  const ZebraStatusAssets._();

  static const package = 'dcs_zebra';
  static const basePath = 'assets/images/icons';

  static String unknown() => '$basePath/unknown.png';

  static String forRole(
    ZebraPrinterRole role,
    ZebraDeviceVisualStatus status,
  ) {
    final code = switch (role) {
      ZebraPrinterRole.boardingPass => 'bp',
      ZebraPrinterRole.bagTag => 'bt',
      ZebraPrinterRole.generic => 'bp',
    };
    return '$basePath/$code/${code}_${status.fileSuffix}.png';
  }

  static String forPrinterStatus(ZebraPrinterStatus status) {
    return forRole(
      status.printer.role,
      visualStatusForPrinterStatus(status),
    );
  }

  static ZebraDeviceVisualStatus visualStatusForPrinterStatus(
    ZebraPrinterStatus status,
  ) {
    if (status.lastError != null || status.state == ZebraPrinterState.failed) {
      return ZebraDeviceVisualStatus.failed;
    }
    if (status.printing || status.state == ZebraPrinterState.printing) {
      return ZebraDeviceVisualStatus.printing;
    }
    if (status.paperOut) return ZebraDeviceVisualStatus.paperOut;
    if (status.headOpen) return ZebraDeviceVisualStatus.open;
    if (status.ribbonOut || status.paused) {
      return ZebraDeviceVisualStatus.jammed;
    }
    final hardware = status.hardwareStatusLabel?.trim().toLowerCase();
    if (hardware != null && hardware.isNotEmpty) {
      if (hardware.contains('paper') && hardware.contains('out')) {
        return ZebraDeviceVisualStatus.paperOut;
      }
      if (hardware.contains('head') && hardware.contains('open')) {
        return ZebraDeviceVisualStatus.open;
      }
      if (hardware.contains('jam') || hardware.contains('ribbon')) {
        return ZebraDeviceVisualStatus.jammed;
      }
      if (hardware.contains('print')) return ZebraDeviceVisualStatus.printing;
      if (hardware.contains('ready') || hardware.contains('active')) {
        return ZebraDeviceVisualStatus.active;
      }
    }
    return switch (status.state) {
      ZebraPrinterState.unknown ||
      ZebraPrinterState.discovered => ZebraDeviceVisualStatus.natural,
      ZebraPrinterState.connecting => ZebraDeviceVisualStatus.initializing,
      ZebraPrinterState.connected ||
      ZebraPrinterState.ready => ZebraDeviceVisualStatus.active,
      ZebraPrinterState.busy => ZebraDeviceVisualStatus.configuring,
      ZebraPrinterState.degraded => ZebraDeviceVisualStatus.inUse,
      ZebraPrinterState.disconnected => ZebraDeviceVisualStatus.disconnect,
      ZebraPrinterState.failed => ZebraDeviceVisualStatus.failed,
      ZebraPrinterState.printing => ZebraDeviceVisualStatus.printing,
    };
  }
}
