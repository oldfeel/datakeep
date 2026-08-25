package site.datakeep.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import site.datakeep.MainActivity
import site.datakeep.R
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/**
 * 前台服务：在进程内运行 gomobile Syncthing（不再 exec libsyncthing.so）。
 */
class SyncthingService : Service() {

    companion object {
        private const val TAG = "SyncthingService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "syncthing_service_channel"
        private const val CHANNEL_NAME = "文件同步"

        const val ACTION_START = "site.datakeep.service.START"
        const val ACTION_STOP = "site.datakeep.service.STOP"
        const val ACTION_RESTART = "site.datakeep.service.RESTART"

        init {
            // 尽早装 SIGSYS 处理，避免服务线程进 gomobile 前被 seccomp 杀掉
            try {
                System.loadLibrary("sigsys_handler")
            } catch (_: Throwable) {
            }
        }
    }

    enum class State { INIT, STARTING, ACTIVE, STOPPING, STOPPED, ERROR }

    private var currentState = State.INIT
    private val binder = SyncthingServiceBinder()
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "SyncthingEngine").apply { isDaemon = true }
    }
    private val wakeLockRef = AtomicReference<PowerManager.WakeLock?>()
    private val multicastLockRef = AtomicReference<WifiManager.MulticastLock?>()

    inner class SyncthingServiceBinder : Binder() {
        fun getService(): SyncthingService = this@SyncthingService
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startSyncthing()
            ACTION_STOP -> stopSyncthing()
            ACTION_RESTART -> restartSyncthing()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        stopEngineOnly()
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun startSyncthing() {
        if (currentState == State.ACTIVE && SyncthingEngine.isRunning()) {
            Log.i(TAG, "Syncthing 已在运行，跳过")
            return
        }

        Log.i(TAG, "启动 Syncthing（gomobile 进程内）")
        currentState = State.STARTING
        startForeground(NOTIFICATION_ID, createNotification("正在启动 Syncthing..."))

        executor.execute {
            try {
                ConfigHelper.ensureConfigExists(this)
                ConfigHelper.ensureLocalDeviceName(this)
                ConfigHelper.ensureNoQuicListenAddresses(this)
                ConfigHelper.ensureAndroidFoldersReady(this)
                acquireWakeLock()
                acquireMulticastLock()
                SyncthingEngine.start(this)
                currentState = State.ACTIVE
                updateNotification("Syncthing 正在运行")
            } catch (e: Exception) {
                Log.e(TAG, "启动 Syncthing 失败", e)
                currentState = State.ERROR
                releaseMulticastLock()
                releaseWakeLock()
                updateNotification("Syncthing 启动失败: ${e.message ?: ""}")
            }
        }
    }

    private fun stopEngineOnly() {
        currentState = State.STOPPING
        try {
            SyncthingEngine.stop()
        } catch (e: Exception) {
            Log.e(TAG, "停止 Syncthing 失败", e)
        } finally {
            releaseMulticastLock()
            releaseWakeLock()
            currentState = State.STOPPED
        }
    }

    private fun restartSyncthing() {
        executor.execute {
            stopEngineOnly()
            try {
                Thread.sleep(500)
            } catch (_: InterruptedException) {
            }
            // 回到主线程发 START，走统一路径
            android.os.Handler(mainLooper).post { startSyncthing() }
        }
    }

    private fun stopSyncthing() {
        executor.execute {
            stopEngineOnly()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    fun isRunning(): Boolean = currentState == State.ACTIVE && SyncthingEngine.isRunning()

    fun getSyncthingInfo(): String = when (currentState) {
        State.ACTIVE -> "running"
        State.STARTING -> "starting"
        State.STOPPING -> "stopping"
        State.ERROR -> "error"
        else -> "stopped"
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DataKeep:SyncthingEngine")
            wl.acquire()
            wakeLockRef.getAndSet(wl)?.let { old ->
                if (old.isHeld) old.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "wakeLock 失败", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLockRef.getAndSet(null)?.let { wl ->
                if (wl.isHeld) wl.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "release wakeLock 失败", e)
        }
    }

    /** WiFi 组播锁：局域网 discovery beacon 依赖 UDP multicast */
    private fun acquireMulticastLock() {
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return
            val lock = wifi.createMulticastLock("DataKeep:SyncthingDiscovery").apply {
                setReferenceCounted(false)
                acquire()
            }
            multicastLockRef.getAndSet(lock)?.let { old ->
                if (old.isHeld) old.release()
            }
            Log.i(TAG, "已获取 MulticastLock")
        } catch (e: Exception) {
            Log.w(TAG, "MulticastLock 失败", e)
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLockRef.getAndSet(null)?.let { lock ->
                if (lock.isHeld) lock.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "release MulticastLock 失败", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Syncthing 文件同步服务"
                setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun createNotification(content: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("文件管理")
            .setContentText(content)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(content: String) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, createNotification(content))
    }
}
