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
    if (status.printing) {
      return CuppsDeviceVisualStatus.printing;
    }
    if (status.configuring) {
      return CuppsDeviceVisualStatus.configuring;
    }

    final hardware = status.hardwareStatusLabel?.trim().toLowerCase() ?? '';
    final errorText = '${status.lastError ?? ''}'.trim().toLowerCase();
    final blob = '$hardware $errorText'.trim();

    // Hardware conditions first — paper/lid/jam must win over generic lastError.
    final condition = _visualFromHardwareBlob(blob);
    if (condition != null) return condition;

    // Lock held by this app is healthy (esp. BC). Do not treat as disconnect/off.
    if ((status.locked || status.state == CuppsDeviceState.locked) &&
        status.acquired) {
      return CuppsDeviceVisualStatus.active;
    }
    if (status.locked || status.state == CuppsDeviceState.locked) {
      return CuppsDeviceVisualStatus.locked;
    }

    if (status.state == CuppsDeviceState.failed) {
      return CuppsDeviceVisualStatus.failed;
    }
    // Soft lastError (e.g. OK-deviceAlreadyLocked) should not paint red ERR when
    // the device is otherwise operational.
    if (status.lastError != null &&
        status.state != CuppsDeviceState.initialized &&
        status.state != CuppsDeviceState.locked &&
        status.state != CuppsDeviceState.dataAvailable &&
        status.state != CuppsDeviceState.busy) {
      return CuppsDeviceVisualStatus.failed;
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

  static CuppsDeviceVisualStatus? _visualFromHardwareBlob(String blob) {
    if (blob.isEmpty) return null;
    if (blob.contains('paperjam') ||
        blob.contains('paper jam') ||
        (blob.contains('jam') && !blob.contains('already'))) {
      return CuppsDeviceVisualStatus.jammed;
    }
    if (blob.contains('paperout') ||
        blob.contains('paper out') ||
        blob.contains('paper_out') ||
        (blob.contains('paper') && blob.contains('out'))) {
      return CuppsDeviceVisualStatus.paperOut;
    }
    if (blob.contains('lid') ||
        blob.contains('cover') ||
        blob.contains('head lifted') ||
        blob.contains('platen') ||
        blob.contains('door open') ||
        (blob.contains('open') && !blob.contains('offline'))) {
      return CuppsDeviceVisualStatus.open;
    }
    if (CuppsHardwareStatus.isOffline(blob)) {
      return CuppsDeviceVisualStatus.disconnect;
    }
    if (blob.contains('ready') || blob == 'active' || blob.contains('device is ready')) {
      return CuppsDeviceVisualStatus.active;
    }
    return null;
  }
}
