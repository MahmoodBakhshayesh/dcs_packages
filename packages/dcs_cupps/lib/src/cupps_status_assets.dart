import 'cupps_models.dart';

enum CuppsDeviceVisualStatus {
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

  const CuppsDeviceVisualStatus(this.fileSuffix);

  final String fileSuffix;
}

class CuppsStatusAssets {
  const CuppsStatusAssets._();

  static const package = 'dcs_cupps';
  static const basePath = 'assets/images/icons';

  static String unknown() => '$basePath/unknown.png';

  static String forDeviceCode(
    String deviceCode,
    CuppsDeviceVisualStatus status,
  ) {
    return '$basePath/$deviceCode/${deviceCode}_${status.fileSuffix}.png';
  }

  static String forDeviceType(
    CuppsDeviceType type,
    CuppsDeviceVisualStatus status,
  ) {
    if (type == CuppsDeviceType.unknown) return unknown();
    return forDeviceCode(type.code, status);
  }

  static String forDeviceStatus(CuppsDeviceStatus status) {
    return forDeviceType(
      status.device.type,
      visualStatusForDeviceStatus(status),
    );
  }

  static CuppsDeviceVisualStatus visualStatusForDeviceStatus(
    CuppsDeviceStatus status,
  ) {
    if (status.lastError != null || status.state == CuppsDeviceState.failed) {
      return CuppsDeviceVisualStatus.failed;
    }
    if (status.printing) {
      return CuppsDeviceVisualStatus.printing;
    }
    if (status.configuring) {
      return CuppsDeviceVisualStatus.configuring;
    }
    final hardware = status.hardwareStatusLabel?.trim().toLowerCase();
    if (hardware != null && hardware.isNotEmpty) {
      if (hardware.contains('paper') && hardware.contains('out')) {
        return CuppsDeviceVisualStatus.paperOut;
      }
      if (hardware.contains('jam')) return CuppsDeviceVisualStatus.jammed;
      if (hardware.contains('open')) return CuppsDeviceVisualStatus.open;
      if (hardware.contains('print')) return CuppsDeviceVisualStatus.printing;
      // Platform `ready="true"` / "Device is Ready" — prefer over lock badge.
      if (hardware.contains('ready') || hardware.contains('active')) {
        return CuppsDeviceVisualStatus.active;
      }
      if (hardware.contains('offline') || hardware.contains('power')) {
        return CuppsDeviceVisualStatus.disconnect;
      }
    }
    // Lock held by this app means the device is ours and operational — ready.
    if ((status.locked || status.state == CuppsDeviceState.locked) &&
        status.acquired) {
      return CuppsDeviceVisualStatus.active;
    }
    if (status.locked || status.state == CuppsDeviceState.locked) {
      return CuppsDeviceVisualStatus.locked;
    }
    return switch (status.state) {
      CuppsDeviceState.unknown ||
      CuppsDeviceState.discovered => CuppsDeviceVisualStatus.natural,
      CuppsDeviceState.connecting ||
      CuppsDeviceState.initializing ||
      CuppsDeviceState.acquiring => CuppsDeviceVisualStatus.initializing,
      CuppsDeviceState.connected ||
      CuppsDeviceState.initialized ||
      CuppsDeviceState.acquired => CuppsDeviceVisualStatus.active,
      CuppsDeviceState.locking ||
      CuppsDeviceState.busy => CuppsDeviceVisualStatus.configuring,
      CuppsDeviceState.locked => CuppsDeviceVisualStatus.locked,
      CuppsDeviceState.dataAvailable => CuppsDeviceVisualStatus.dataAvailable,
      CuppsDeviceState.degraded => CuppsDeviceVisualStatus.inUse,
      CuppsDeviceState.disconnected => CuppsDeviceVisualStatus.disconnect,
      CuppsDeviceState.failed => CuppsDeviceVisualStatus.failed,
    };
  }
}
