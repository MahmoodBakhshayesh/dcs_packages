import 'package:flutter/foundation.dart';

import 'package:dcs_device_util/dcs_device_util.dart';

Future<void> main() async {
  final controller = DcsDeviceController(
    configStore: const SharedPreferencesDcsConfigStore(),
    initialConfig: const DcsDeviceConfig(
      profiles: [
        DcsDeviceProfile(
          id: 'boarding-reader',
          label: 'Boarding Reader',
          kind: DcsDeviceKind.reader,
          matcher: DcsDeviceMatcher(productName: 'Reader'),
        ),
        DcsDeviceProfile(
          id: 'bag-printer',
          label: 'Bag Tag Printer',
          kind: DcsDeviceKind.printer,
          serialOptions: DcsSerialOptions(
            baudRate: 9600,
            flowControl: DcsSerialFlowControl.none,
          ),
          matcher: DcsDeviceMatcher(manufacturer: 'Zebra'),
        ),
      ],
    ),
    logger: (event) {
      // Replace with your application logger in production.
      debugPrint('[${event.level.name}] ${event.message}');
    },
  );

  controller.statuses.listen((statuses) {
    for (final status in statuses.values) {
      debugPrint(
        '${status.profileId}: ${status.state.name} - ${status.message}',
      );
    }
  });

  await controller.start();

  final response = await controller.sendTextRequest(
    'boarding-reader',
    'AV',
    options: const DcsDeviceRequestOptions(
      timeout: Duration(seconds: 2),
      quietWindow: Duration(milliseconds: 150),
      framed: true,
    ),
  );
  debugPrint('Reader response: ${response.status.name} ${response.text}');

  // Send raw bytes to a connected device when needed.
  // await controller.send('bag-printer', [0x1B, 0x40]);
}
