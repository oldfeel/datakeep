package site.datakeep.service

import android.content.Context
import android.util.Log
import mdst.Client
import mdst.Mdst

/**
 * 进程内 Syncthing（gomobile AAR：mdst.Client），与 iOS 共用 syncthing_core。
 */
object SyncthingEngine {
    private const val TAG = "SyncthingEngine"

    @Volatile
    private var client: Client? = null

    @Synchronized
    fun start(context: Context) {
        val existing = client
        if (existing != null && existing.isRunning) {
            Log.i(TAG, "已在运行，跳过启动")
            return
        }

        val app = context.applicationContext
        val home = app.filesDir.absolutePath
        val files = app.getExternalFilesDir(null)?.absolutePath ?: home

        Log.i(TAG, "启动 gomobile Syncthing home=$home files=$files")
        val c = Mdst.newClient(home, files)
            ?: throw Exception("Mdst.newClient 返回 null")
        c.setDeviceName(ConfigHelper.getPhoneDeviceName(app))
        try {
            c.start()
        } catch (e: Exception) {
            val detail = try {
                c.lastError()
            } catch (_: Exception) {
                null
            }
            throw Exception(detail?.takeIf { it.isNotEmpty() } ?: e.message ?: "Start failed", e)
        }
        client = c
        Log.i(TAG, "Syncthing 已启动 deviceID=${c.deviceID()}")
    }

    @Synchronized
    fun stop() {
        try {
            client?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "stop 异常", e)
        } finally {
            client = null
        }
    }

    fun isRunning(): Boolean = try {
        client?.isRunning == true
    } catch (_: Exception) {
        false
    }

    fun deviceId(): String = try {
        client?.deviceID() ?: ""
    } catch (_: Exception) {
        ""
    }
}
