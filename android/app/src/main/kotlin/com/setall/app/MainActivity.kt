package com.setall.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Platform channel: exposes Android region locale (Locale.getDefault()) to Dart.
        // Locale.getDefault() reflects the device Region setting,
        // which is independent of the preferred language list that Flutter's PlatformDispatcher.locale uses.
        val regionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.setall.app/region"
        )
        regionChannel.setMethodCallHandler { call, result ->
            if (call.method == "getRegionLocale") {
                result(Locale.getDefault().toString())
            } else {
                result.notImplemented()
            }
        }
    }
}
