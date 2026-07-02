import 'package:dcs_common/dcs_common.dart';

import 'dcs_models.dart';

class DcsStandardDeviceLogSink {
  const DcsStandardDeviceLogSink({required this.store});

  final DcsStandardLogStore store;

  Future<void> call(DcsLogEvent event) {
    return store.writeBoth(
      DcsStandardLogEvent.now(
        module: DcsPackageModule.deviceUtil,
        severity: _severity(event.level),
        operation: event.data['operation']?.toString() ?? 'device',
        deviceId: event.profileId,
        message: event.message,
        error: event.error,
        stackTrace: event.stackTrace,
        data: event.data,
      ),
    );
  }

  DcsLogSeverity _severity(DcsLogLevel level) {
    return switch (level) {
      DcsLogLevel.trace => DcsLogSeverity.trace,
      DcsLogLevel.debug => DcsLogSeverity.debug,
      DcsLogLevel.info => DcsLogSeverity.info,
      DcsLogLevel.warning => DcsLogSeverity.warning,
      DcsLogLevel.error => DcsLogSeverity.error,
    };
  }
}
