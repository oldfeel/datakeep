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
import tech.shupi.mydata.R
import java.util.concurrent.atomic.AtomicReference
import tech.shupi.mydata.service.HttpsApiController

/**
 * 前台服务，用于运行 Syncthing 原生二进制文件
 * 参考 syncthing-android 的实现
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
    private val syncthingRunnable = AtomicReference<SyncthingRunnable>()
    private var syncthingThread: Thread? = null
    private val binder = SyncthingServiceBinder()
    
    // HTTPS API 服务器
    private var httpsApiController: HttpsApiController? = null

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
     * 启动 Syncthing
     */
    private fun startSyncthing() {
        if (currentState == State.ACTIVE || currentState == State.STARTING) {
            Log.w(TAG, "⚠️ Syncthing 已经在运行或正在启动")
            return
        }

        Log.i(TAG, "🚀 开始启动 Syncthing 服务")
        updateState(State.STARTING)
        
        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification("正在启动 Syncthing..."))

        try {
            Log.i(TAG, "🔧 创建 SyncthingRunnable 实例...")
            // 创建并启动 SyncthingRunnable
            val runnable = SyncthingRunnable(this, SyncthingRunnable.Command.MAIN)
            syncthingRunnable.set(runnable)
            
            Log.i(TAG, "🧵 创建并启动 Syncthing 线程...")
            syncthingThread = Thread(runnable).apply {
                name = "SyncthingThread"
                start()
            }
            
            Log.i(TAG, "✅ Syncthing 线程启动成功")
            Log.i(TAG, "🆔 线程名称: ${syncthingThread?.name}")
            Log.i(TAG, "📊 线程状态: ${syncthingThread?.state}")
            
            // 启动 HTTPS API 服务器
            startHttpsServer()
            
            // 更新状态为运行中
            updateState(State.ACTIVE)
            updateNotification("Syncthing 正在运行")
            
        } catch (e: Exception) {
            Log.e(TAG, "启动 Syncthing 失败", e)
            updateState(State.ERROR)
            updateNotification("Syncthing 启动失败")
        }
    }

    /**
     * 停止 Syncthing
     */
    private fun stopSyncthing() {
        Log.i(TAG, "停止 Syncthing")
        updateState(State.STOPPING)
        updateNotification("正在停止 Syncthing...")

        try {
            // 停止 Syncthing 进程
            syncthingRunnable.get()?.killSyncthing()
            
            // 等待线程结束
            syncthingThread?.join(5000) // 最多等待5秒
            
            syncthingRunnable.set(null)
            syncthingThread = null
            
            updateState(State.STOPPED)
            
        } catch (e: Exception) {
            Log.e(TAG, "停止 Syncthing 失败", e)
            updateState(State.ERROR)
        } finally {
            // 停止 HTTPS 服务器
            stopHttpsServer()
            
            // 停止前台服务
            stopForeground(true)
            stopSelf()
        }
    }

    /**
     * 重启 Syncthing
     */
    private fun restartSyncthing() {
        Log.i(TAG, "重启 Syncthing")
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
        
        // 这里可以发送事件到 React Native
        // 例如通过 EventEmitter 或 NativeModule
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
        val intent = Intent(this, tech.shupi.mydata.MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MyDataApp")
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_notification)
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
     * 获取 Syncthing 进程信息
     */
    fun getSyncthingInfo(): String {
        return when (currentState) {
            State.INIT -> "未启动"
            State.STARTING -> "正在启动..."
            State.ACTIVE -> "运行中"
            State.STOPPING -> "正在停止..."
            State.STOPPED -> "已停止"
            State.ERROR -> "错误状态"
        }
    }
    
    /**
     * 启动 HTTPS API 服务器
     */
    private fun startHttpsServer() {
        Log.d(TAG, "🚀 开始启动 HTTPS API 服务器...")
        
        try {
            if (httpsApiController != null) {
                Log.w(TAG, "⚠️ HTTPS 服务器已经在运行")
                return
            }
            
            Log.d(TAG, "🔧 创建 HttpsApiController 实例...")
            // 创建并启动 HTTPS 服务器
            httpsApiController = HttpsApiController(this)
            Log.d(TAG, "✅ HttpsApiController 实例创建成功")
            
            Log.d(TAG, "🚀 调用 HttpsApiController.start()...")
            httpsApiController?.start()
            
            Log.i(TAG, "✅ HTTPS API 服务器启动成功！")
            Log.i(TAG, "📡 服务器地址: https://127.0.0.1:8443")
            Log.i(TAG, "🌐 可用端点: /api/devices, /api/device/*/folders, /api/folder/*")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 启动 HTTPS 服务器失败", e)
            Log.e(TAG, "错误详情: ${e.message}")
            Log.e(TAG, "堆栈跟踪:")
            e.printStackTrace()
        }
    }
    
    /**
     * 停止 HTTPS API 服务器
     */
    private fun stopHttpsServer() {
        try {
            if (httpsApiController != null) {
                httpsApiController?.stop()
                httpsApiController = null
                Log.i(TAG, "HTTPS API 服务器已停止")
            }
        } catch (e: Exception) {
            Log.e(TAG, "停止 HTTPS 服务器失败", e)
        }
    }
} 