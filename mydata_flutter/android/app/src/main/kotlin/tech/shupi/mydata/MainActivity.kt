package tech.shupi.mydata

import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import tech.shupi.mydata.service.ConfigHelper
import tech.shupi.mydata.service.Constants
import tech.shupi.mydata.service.SyncthingService
import java.io.File

class MainActivity : FlutterActivity() {
    private val channel = "tech.shupi.mydata/api"
    private val tag = "MainActivity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "startSyncthingService" -> {
                    try {
                        startSyncthingService()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(tag, "启动 Syncthing 失败", e)
                        result.success(false)
                    }
                }
                "stopSyncthingService" -> {
                    try {
                        val intent = Intent(this, SyncthingService::class.java).apply {
                            action = SyncthingService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getServiceStatus" -> {
                    result.success("running")
                }
                "getSyncthingConfigPath" -> {
                    Log.i(tag, "getSyncthingConfigPath: 修正本机设备名…")
                    ConfigHelper.ensureLocalDeviceName(this)
                    val config = File(filesDir, Constants.CONFIG_FILE)
                    val deviceName = ConfigHelper.getPhoneDeviceName(this)
                    Log.i(tag, "getSyncthingConfigPath => ${config.absolutePath}, deviceName=$deviceName")
                    result.success(
                        mapOf(
                            "path" to config.absolutePath,
                            "deviceName" to deviceName,
                        )
                    )
                }
                "getDefaultDeviceName" -> {
                    val name = ConfigHelper.getPhoneDeviceName(this)
                    Log.i(tag, "getDefaultDeviceName => $name (MODEL=${android.os.Build.MODEL})")
                    result.success(name)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startSyncthingService() {
        Log.i(tag, "启动 Syncthing 前台服务")
        val intent = Intent(this, SyncthingService::class.java).apply {
            action = SyncthingService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
