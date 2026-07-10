import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Platform channel: exposes iOS region locale (Locale.current.identifier) to Dart.
    // Locale.current reflects the Region setting in Settings → General → Language & Region,
    // which is independent of the preferred language list that Flutter's PlatformDispatcher.locale uses.
    if let controller = window?.rootViewController as? FlutterViewController {
      let regionChannel = FlutterMethodChannel(
        name: "com.setall.app/region",
        binaryMessenger: controller.binaryMessenger
      )
      regionChannel.setMethodCallHandler { (call, result) in
        if call.method == "getRegionLocale" {
          result(Locale.current.identifier)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
