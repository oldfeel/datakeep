package tech.shupi.mydata

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import tech.shupi.mydata.service.SyncthingService

class MainActivity: FlutterActivity() {
    private val CHANNEL = "tech.shupi.mydata/api"
    private val TAG = "MainActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate - 自动启动 Syncthing 服务")
        // 应用启动时自动启动 Syncthing 服务
        startSyncthingService()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startSyncthingService" -> {
                    startSyncthingService()
                    result.success(true)
                }
                "stopSyncthingService" -> {
                    stopSyncthingService()
                    result.success(true)
                }
                "getServiceStatus" -> {
                    val status = getServiceStatus()
                    result.success(status)
                }
                "getApiBaseUrl" -> {
                    val url = "https://127.0.0.1:8443/api"
                    result.success(url)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startSyncthingService() {
        try {
            Log.i(TAG, "🚀 启动 Syncthing 服务")
            val intent = Intent(this, SyncthingService::class.java).apply {
                action = SyncthingService.ACTION_START
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.i(TAG, "✅ Syncthing 服务启动请求已发送")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 启动 Syncthing 服务失败", e)
        }
    }

    private fun stopSyncthingService() {
        Log.d(TAG, "停止 Syncthing 服务")
        val intent = Intent(this, SyncthingService::class.java).apply {
            action = SyncthingService.ACTION_STOP
        }
        stopService(intent)
    }

    private fun getServiceStatus(): String {
        // 尝试获取服务状态（需要绑定服务才能获取）
        return "unknown"
    }
}
