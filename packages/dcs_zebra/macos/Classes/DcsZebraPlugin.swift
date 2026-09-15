import FlutterMacOS
import Foundation

public class DcsZebraPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dcs_zebra", binaryMessenger: registrar.messenger)
    let instance = DcsZebraPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      result([
        "tcp": true,
        "bluetooth": false,
        "bluetoothLe": false,
        "usb": false,
      ])
    case "discover":
      result([])
    case "connect", "disconnect", "write", "read", "getStatus":
      result(FlutterError(
        code: "unsupported",
        message: "macOS has no official Zebra Link-OS SDK. Use Dart TCP for network printers.",
        details: nil
      ))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
