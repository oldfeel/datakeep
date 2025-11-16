package tech.shupi.mydata.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import tech.shupi.mydata.MainActivity

/**
 * 前台服务，用于管理 gomobile backend（Syncthing + HTTPS API 服务器）
 */
class SyncthingService : Service() {

    companion object {
        private const val TAG = "SyncthingService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "syncthing_service_channel"
        private const val CHANNEL_NAME = "Syncthing Service"
        
        // Intent Actions
        const val ACTION_START = "tech.shupi.mydata.service.START"
        const val ACTION_STOP = "tech.shupi.mydata.service.STOP"
        const val ACTION_RESTART = "tech.shupi.mydata.service.RESTART"
    }

    /**
     * 服务状态枚举
     */
    enum class State {
        INIT,           // 初始化
        STARTING,       // 正在启动
        ACTIVE,         // 运行中
        STOPPING,       // 正在停止
        STOPPED,        // 已停止
        ERROR           // 错误状态
    }

    private var currentState = State.INIT
    private val binder = SyncthingServiceBinder()
    
    // gomobile backend 服务
    private var backendService: BackendService? = null

    /**
     * 服务绑定器
     */
    inner class SyncthingServiceBinder : Binder() {
        fun getService(): SyncthingService = this@SyncthingService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START -> {
                startSyncthing()
            }
            ACTION_STOP -> {
                stopSyncthing()
            }
            ACTION_RESTART -> {
                restartSyncthing()
            }
        }
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        stopSyncthing()
        super.onDestroy()
    }

    /**
     * 启动 Syncthing 和 HTTPS API 服务器（使用 gomobile backend）
     */
    private fun startSyncthing() {
        if (currentState == State.ACTIVE || currentState == State.STARTING) {
            Log.w(TAG, "⚠️ 服务已经在运行或正在启动")
            return
        }

        Log.i(TAG, "🚀 开始启动服务（使用 gomobile backend）")
        updateState(State.STARTING)
        
        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification("正在启动服务..."))

        try {
            // 使用 gomobile backend
            backendService = BackendService(this)
            val error = backendService!!.start()
            
            if (error.isEmpty()) {
                Log.i(TAG, "✅ Backend 服务启动成功")
                updateState(State.ACTIVE)
                updateNotification("服务正在运行")
            } else {
                Log.e(TAG, "❌ Backend 服务启动失败: $error")
                updateState(State.ERROR)
                updateNotification("服务启动失败: $error")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ 启动服务失败", e)
            updateState(State.ERROR)
            updateNotification("服务启动失败: ${e.message}")
        }
    }

    /**
     * 停止 Syncthing 和 HTTPS API 服务器
     */
    private fun stopSyncthing() {
        Log.i(TAG, "停止服务")
        updateState(State.STOPPING)
        updateNotification("正在停止服务...")

        try {
            if (backendService != null) {
                val error = backendService!!.stop()
                if (error.isEmpty()) {
                    Log.i(TAG, "✅ Backend 服务停止成功")
                } else {
                    Log.e(TAG, "❌ Backend 服务停止失败: $error")
                }
                backendService = null
                updateState(State.STOPPED)
            }
        } catch (e: Exception) {
            Log.e(TAG, "停止服务失败", e)
            updateState(State.ERROR)
        } finally {
            // 停止前台服务
            stopForeground(true)
            stopSelf()
        }
    }

    /**
     * 重启服务
     */
    private fun restartSyncthing() {
        Log.i(TAG, "重启服务")
        stopSyncthing()
        
        // 延迟启动，确保完全停止
        android.os.Handler(mainLooper).postDelayed({
            startSyncthing()
        }, 1000)
    }

    /**
     * 更新服务状态
     */
    private fun updateState(newState: State) {
        currentState = newState
        Log.d(TAG, "服务状态更新: $newState")
        
        // 这里可以发送事件到 Flutter
        // 例如通过 MethodChannel 或 EventChannel
    }

    /**
     * 创建通知渠道（Android 8.0+）
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Syncthing 文件同步服务"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * 创建通知
     */
    private fun createNotification(content: String): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 使用系统默认图标（Flutter 应用图标）
        val iconId = applicationInfo.icon
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MyDataApp")
            .setContentText(content)
            .setSmallIcon(iconId)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    /**
     * 更新通知内容
     */
    private fun updateNotification(content: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification(content))
    }

    /**
     * 获取当前状态
     */
    fun getCurrentState(): State = currentState

    /**
     * 检查是否正在运行
     */
    fun isRunning(): Boolean = currentState == State.ACTIVE

    /**
     * 获取服务状态信息
     */
    fun getServiceInfo(): String {
        return when (currentState) {
            State.INIT -> "未启动"
            State.STARTING -> "正在启动..."
            State.ACTIVE -> "运行中"
            State.STOPPING -> "正在停止..."
            State.STOPPED -> "已停止"
            State.ERROR -> "错误状态"
        }
    }
}

