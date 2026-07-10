import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Retain the channel for the app's lifetime so its handler isn't released.
  private var regionChannel: FlutterMethodChannel?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register the region channel on the ACTUAL implicit engine. Under this
    // embedding window?.rootViewController is nil in didFinishLaunchingWithOptions,
    // so the previous registration silently no-op'd → MissingPluginException.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SetAllRegionChannel") {
      let channel = FlutterMethodChannel(
        name: "com.setall.app/region",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { (call, result) in
        if call.method == "getRegionLocale" {
          let ident = Locale.current.identifier
          // A DateFormatter INSTANCE with .short timeStyle honors the system
          // 24-Hour Time toggle (the class method dateFormat(fromTemplate:) does not).
          let probe = DateFormatter()
          probe.locale = Locale.current
          probe.dateStyle = .none
          probe.timeStyle = .short
          let sample = probe.string(from: Date())
          let hasMeridiem =
              (!probe.amSymbol.isEmpty && sample.contains(probe.amSymbol)) ||
              (!probe.pmSymbol.isEmpty && sample.contains(probe.pmSymbol))
          let is24 = !hasMeridiem
          let sep = ident.contains("@") ? ";" : "@"
          NSLog("[SetAll] region getRegionLocale -> \(ident)\(sep)hours=\(is24 ? "h23" : "h12")  (sample=\(sample))")
          result("\(ident)\(sep)hours=\(is24 ? "h23" : "h12")")
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      self.regionChannel = channel
    }
  }
}
