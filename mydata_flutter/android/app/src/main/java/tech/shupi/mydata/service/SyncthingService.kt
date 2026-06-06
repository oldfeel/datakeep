package tech.shupi.mydata.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import tech.shupi.mydata.MainActivity
import tech.shupi.mydata.R
import java.util.concurrent.atomic.AtomicReference

/** 前台服务，运行 Syncthing 原生库 */
class SyncthingService : Service() {

    companion object {
        private const val TAG = "SyncthingService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "syncthing_service_channel"
        private const val CHANNEL_NAME = "Syncthing Service"

        const val ACTION_START = "tech.shupi.mydata.service.START"
        const val ACTION_STOP = "tech.shupi.mydata.service.STOP"
        const val ACTION_RESTART = "tech.shupi.mydata.service.RESTART"
    }

    enum class State { INIT, STARTING, ACTIVE, STOPPING, STOPPED, ERROR }

    private var currentState = State.INIT
    private val syncthingRunnable = AtomicReference<SyncthingRunnable>()
    private var syncthingThread: Thread? = null
    private val binder = SyncthingServiceBinder()

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
        stopSyncthing()
        super.onDestroy()
    }

    private fun startSyncthing() {
        if (currentState == State.ACTIVE || currentState == State.STARTING) return

        Log.i(TAG, "启动 Syncthing")
        currentState = State.STARTING
        startForeground(NOTIFICATION_ID, createNotification("正在启动 Syncthing..."))

        try {
            val runnable = SyncthingRunnable(this, SyncthingRunnable.Command.MAIN)
            syncthingRunnable.set(runnable)
            syncthingThread = Thread(runnable, "SyncthingThread").apply { start() }
            currentState = State.ACTIVE
            updateNotification("Syncthing 正在运行")
        } catch (e: Exception) {
            Log.e(TAG, "启动 Syncthing 失败", e)
            currentState = State.ERROR
            updateNotification("Syncthing 启动失败")
        }
    }

    private fun stopSyncthing() {
        currentState = State.STOPPING
        try {
            syncthingRunnable.get()?.killSyncthing()
            syncthingThread?.join(5000)
            syncthingRunnable.set(null)
            syncthingThread = null
            currentState = State.STOPPED
        } catch (e: Exception) {
            Log.e(TAG, "停止 Syncthing 失败", e)
            currentState = State.ERROR
        } finally {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun restartSyncthing() {
        stopSyncthing()
        android.os.Handler(mainLooper).postDelayed({ startSyncthing() }, 1000)
    }

    fun isRunning(): Boolean = currentState == State.ACTIVE

    fun getSyncthingInfo(): String = when (currentState) {
        State.ACTIVE -> "running"
        State.STARTING -> "starting"
        State.STOPPING -> "stopping"
        State.ERROR -> "error"
        else -> "stopped"
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
            .setContentTitle("MyData")
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
