import 'models.dart';
import 'arinc/arinc_device.dart';
import 'resa/resa_device.dart';
import 'sita/sita_device.dart';

/// Shared CUTE peripheral contract for ARINC / SITA / RESA.
abstract class CutePeripheral {
  CuteVendor get vendor;
  CutePeripheralKind get kind;
  String get displayName;

  Stream<CutePeripheralStatus> get statusChanges;
  CutePeripheralStatus get currentStatus;
  Stream<List<int>> get data;

  Future<void> open();
  Future<void> lock({Duration timeout = const Duration(seconds: 10)});
  Future<void> unlock();

  /// Vendor flush (SITA: `XSPMFlush`; ARINC/RESA: no-op unless overridden).
  Future<void> flush();

  Future<void> write(List<int> bytes, {bool endDoc = false});
  Future<void> writeAea(String command, {bool endDoc = false, bool frame = true});
  Future<List<int>?> read({Duration timeout = const Duration(seconds: 5)});
  Future<CutePeripheralStatus> queryStatus();
  Future<void> close();
  Future<void> dispose();

  static CutePeripheral arinc({
    required CutePeripheralKind kind,
    required CutePeripheralEndpoint endpoint,
    String name = '',
    String aeaContext = 'm/A,001',
  }) =>
      ArincDevice(
        kind: kind,
        endpoint: endpoint,
        name: name.isEmpty ? kind.name.toUpperCase() : name,
        aeaContext: aeaContext,
      );

  static CutePeripheral sita({
    required CutePeripheralIdentity identity,
  }) =>
      SitaDevice(identity: identity);

  static CutePeripheral resa({
    required CutePeripheralIdentity identity,
    bool trace = false,
  }) =>
      ResaDevice(identity: identity, trace: trace);
}
