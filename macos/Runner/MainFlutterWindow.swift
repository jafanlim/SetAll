import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Platform channel: exposes macOS region locale (Locale.current) to Dart.
    // Locale.current reflects the Region setting in System Settings → General → Language & Region,
    // which is independent of the preferred language list that Flutter's PlatformDispatcher.locale uses.
    let regionChannel = FlutterMethodChannel(
      name: "com.setall.app/region",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    regionChannel.setMethodCallHandler { (call, result) in
      if call.method == "getRegionLocale" {
        result(Locale.current.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
