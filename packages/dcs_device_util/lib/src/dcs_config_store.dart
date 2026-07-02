import 'package:shared_preferences/shared_preferences.dart';

import 'dcs_models.dart';

/// Storage boundary for persisted DCS device configuration.
abstract class DcsConfigStore {
  Future<DcsDeviceConfig?> load();

  Future<void> save(DcsDeviceConfig config);

  Future<void> clear();
}

/// SharedPreferences-backed config store for Flutter desktop apps.
class SharedPreferencesDcsConfigStore implements DcsConfigStore {
  const SharedPreferencesDcsConfigStore({
    this.key = 'dcs_device_util.config.v1',
  });

  final String key;

  @override
  Future<DcsDeviceConfig?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(key);
    if (encoded == null || encoded.isEmpty) return null;
    return DcsDeviceConfig.decode(encoded);
  }

  @override
  Future<void> save(DcsDeviceConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, config.encode());
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}
