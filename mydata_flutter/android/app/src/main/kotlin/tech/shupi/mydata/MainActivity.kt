package tech.shupi.mydata

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
// import tech.shupi.mydata.service.SyncthingService  // TODO: 待实现

class MainActivity: FlutterActivity() {
    private val CHANNEL = "tech.shupi.mydata/api"
    private val TAG = "MainActivity"

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
        Log.d(TAG, "启动 Syncthing 服务")
        // TODO: 实现 SyncthingService 后取消注释
        /*
        val intent = Intent(this, SyncthingService::class.java).apply {
            action = SyncthingService.ACTION_START
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        */
        Log.w(TAG, "SyncthingService 尚未实现")
    }

    private fun stopSyncthingService() {
        Log.d(TAG, "停止 Syncthing 服务")
        // TODO: 实现 SyncthingService 后取消注释
        /*
        val intent = Intent(this, SyncthingService::class.java).apply {
            action = SyncthingService.ACTION_STOP
        }
        stopService(intent)
        */
        Log.w(TAG, "SyncthingService 尚未实现")
    }

    private fun getServiceStatus(): String {
        // TODO: 实现服务状态查询
        return "unknown"
    }
}
