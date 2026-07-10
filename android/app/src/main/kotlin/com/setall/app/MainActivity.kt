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
                // Detect 24h vs 12h from the user's system time format setting.
                // android.text.format.DateFormat.is24HourFormat reads the OS toggle directly.
                val is24 = android.text.format.DateFormat.is24HourFormat(this@MainActivity)
                val ident = Locale.getDefault().toString()
                // Append hour-cycle keyword so the Dart resolver picks it up via the
                // existing [@;]hours=(h\d+) regex. Use ";" as separator when "@" is
                // already present to keep the ICU extension valid.
                val sep = if (ident.contains("@")) ";" else "@"
                android.util.Log.d("SetAll", "region getRegionLocale -> $ident${sep}hours=${if (is24) "h23" else "h12"}")
                result("$ident${sep}hours=${if (is24) "h23" else "h12"}")
            } else {
                result.notImplemented()
            }
        }
    }
}
