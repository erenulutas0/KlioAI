package com.example.flutter_vocabmaster

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "klioai/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Firebase Test Lab sets this on every device it runs, and the Play
                    // Console pre-launch report runs on Test Lab. See DeviceEnvironment.
                    "isTestLab" -> result.success(
                        "true" == Settings.System.getString(contentResolver, "firebase.test.lab")
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
