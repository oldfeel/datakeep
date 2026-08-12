package tech.shupi.datakeep

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import tech.shupi.datakeep.service.ConfigHelper
import tech.shupi.datakeep.service.Constants
import tech.shupi.datakeep.service.SyncthingEngine
import tech.shupi.datakeep.service.SyncthingService
import tech.shupi.datakeep.util.PermissionUtil
import tech.shupi.datakeep.util.StoragePathUtils
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val channel = "tech.shupi.datakeep/api"
    private val tag = "MainActivity"
    private var pendingPickResult: MethodChannel.Result? = null

    private val pickFolderLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        val result = pendingPickResult
        pendingPickResult = null
        if (result == null) return@registerForActivityResult

        if (activityResult.resultCode != Activity.RESULT_OK) {
            result.success(null)
            return@registerForActivityResult
        }
        val uri = activityResult.data?.data
        if (uri == null) {
            result.success(null)
            return@registerForActivityResult
        }
        val path = StoragePathUtils.getAbsolutePathFromSafUri(this, uri)
        if (path.isNullOrEmpty()) {
            result.error("PATH_ERROR", "无法解析所选目录", null)
            return@registerForActivityResult
        }
        StoragePathUtils.preCreateFolderMarker(path)
        val writable = StoragePathUtils.nativeCanWriteToPath(path)
        result.success(
            mapOf(
                "path" to path,
                "writable" to writable,
            ),
        )
    }

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
                "restartSyncthingService" -> {
                    try {
                        val intent = Intent(this, SyncthingService::class.java).apply {
                            action = SyncthingService.ACTION_RESTART
                        }
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getServiceStatus" -> {
                    result.success(
                        if (SyncthingEngine.isRunning()) "running" else "stopped",
                    )
                }
                "getSyncthingConfigPath" -> {
                    // 不在 Syncthing 运行时写 config，避免热重启导致 native 崩溃
                    val config = File(filesDir, Constants.CONFIG_FILE)
                    val deviceName = ConfigHelper.getPhoneDeviceName(this)
                    Log.i(tag, "getSyncthingConfigPath => ${config.absolutePath}, deviceName=$deviceName")
                    result.success(
                        mapOf(
                            "path" to config.absolutePath,
                            "deviceName" to deviceName,
                        ),
                    )
                }
                "getDefaultDeviceName" -> {
                    val name = ConfigHelper.getPhoneDeviceName(this)
                    Log.i(tag, "getDefaultDeviceName => $name (MODEL=${android.os.Build.MODEL})")
                    result.success(name)
                }
                "hasAllFilesAccess" -> {
                    result.success(PermissionUtil.haveStoragePermission(this))
                }
                "requestAllFilesAccess" -> {
                    PermissionUtil.requestStoragePermission(this)
                    result.success(true)
                }
                "canWriteToPath" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.success(false)
                    } else {
                        result.success(StoragePathUtils.nativeCanWriteToPath(path))
                    }
                }
                "getDefaultSyncFolderPath" -> {
                    val folderId = call.argument<String>("folderId") ?: "folder"
                    val path = StoragePathUtils.getDefaultSyncFolderPath(this, folderId)
                    File(path).mkdirs()
                    StoragePathUtils.preCreateFolderMarker(path)
                    result.success(path)
                }
                "pickSyncFolder" -> {
                    if (pendingPickResult != null) {
                        result.error("BUSY", "目录选择器已在打开", null)
                        return@setMethodCallHandler
                    }
                    pendingPickResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                        putExtra("android.content.extra.SHOW_ADVANCED", true)
                        StoragePathUtils.getInitialPickerUri(this@MainActivity)?.let { initial ->
                            putExtra("android.provider.extra.INITIAL_URI", initial)
                        }
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                        )
                    }
                    try {
                        pickFolderLauncher.launch(intent)
                    } catch (e: ActivityNotFoundException) {
                        pendingPickResult = null
                        result.error("NO_PICKER", "未找到目录选择器", null)
                    }
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
