package tech.shupi.mydata

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "tech.shupi.mydata/api"
    private val TAG = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startSyncthingService" -> result.success(false)
                "stopSyncthingService" -> result.success(false)
                "getServiceStatus" -> result.success("unknown")
                "getApiBaseUrl" -> result.success("https://127.0.0.1:8443/api")
                else -> result.notImplemented()
            }
        }
    }
}
