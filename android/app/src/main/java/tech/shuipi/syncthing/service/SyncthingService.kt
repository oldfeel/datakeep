package tech.shuipi.syncthing.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import tech.shuipi.syncthing.MainActivity
import java.util.concurrent.atomic.AtomicReference

/**
 * 持有原生 syncthing 实例并提供访问 API
 */
class SyncthingService : Service() {
    
    companion object {
        private const val TAG = "SyncthingService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "syncthing_service_channel"
    }
    
    /**
     * 表示 SyncthingService 和 Syncthing 本身的当前状态
     */
    enum class State {
        INIT,       // 服务正在初始化，Syncthing 尚未启动
        STARTING,   // Syncthing 二进制文件正在启动
        ACTIVE,     // Syncthing 二进制文件正在运行，REST API 可用
        DISABLED,   // Syncthing 二进制文件正在关闭
        ERROR       // 存在阻止 Syncthing 运行的问题
    }
    
    interface OnServiceStateChangeListener {
        fun onServiceStateChange(currentState: State)
    }
    
    private var currentState = State.DISABLED
    private var syncthingRunnable: SyncthingRunnable? = null
    private var syncthingRunnableThread: Thread? = null
    private var httpsApiController: HttpsApiController? = null
    private val handler = Handler(Looper.getMainLooper())
    private val binder = SyncthingServiceBinder(this)
    
    private val onServiceStateChangeListeners = mutableSetOf<OnServiceStateChangeListener>()
    
    override fun onCreate() {
        super.onCreate()
        Log.v(TAG, "onCreate")
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.v(TAG, "onStartCommand: ${intent?.action}")
        
        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification("正在启动 Syncthing..."))
        
        when (intent?.action) {
            Constants.ACTION_RESTART -> {
                restartSyncthing()
            }
            Constants.ACTION_RESET_DATABASE -> {
                resetDatabase()
            }
            Constants.ACTION_RESET_DELTAS -> {
                resetDeltas()
            }
            else -> {
                // 默认启动 Syncthing
                startSyncthing()
            }
        }
        
        return START_STICKY
    }
    
    override fun onBind(intent: Intent): IBinder {
        return binder
    }
    
    override fun onDestroy() {
        Log.v(TAG, "onDestroy")
        super.onDestroy()
        shutdown(State.DISABLED) {
            Log.i(TAG, "Syncthing service destroyed")
        }
    }
    
    /**
     * 启动 Syncthing
     */
    private fun startSyncthing() {
        if (currentState == State.STARTING || currentState == State.ACTIVE) {
            Log.w(TAG, "Syncthing is already running or starting")
            return
        }
        
        Log.i(TAG, "Starting Syncthing")
        onServiceStateChange(State.STARTING)
        
        // 检查配置文件是否存在，如果不存在则生成
        if (!Constants.getConfigFile(this).exists()) {
            Log.i(TAG, "Config file not found, generating initial config")
            generateInitialConfig()
        }
        
        // 启动 Syncthing 主进程
        syncthingRunnable = SyncthingRunnable(this, SyncthingRunnable.Command.MAIN)
        syncthingRunnableThread = Thread(syncthingRunnable).apply {
            name = "SyncthingThread"
            start()
        }
        
        // 启动 HTTPS API Controller
        startHttpsApiController()
        
        // 延迟检查 Syncthing 是否成功启动
        handler.postDelayed({
            checkSyncthingStatus()
        }, 5000) // 5秒后检查
    }
    
    /**
     * 重启 Syncthing
     */
    private fun restartSyncthing() {
        Log.i(TAG, "Restarting Syncthing")
        shutdown(State.STARTING) {
            startSyncthing()
        }
    }
    
    /**
     * 重置数据库
     */
    private fun resetDatabase() {
        Log.i(TAG, "Resetting Syncthing database")
        shutdown(State.INIT) {
            val resetRunnable = SyncthingRunnable(this, SyncthingRunnable.Command.RESET_DATABASE)
            Thread(resetRunnable).apply {
                name = "SyncthingResetThread"
                start()
            }
            // 重置完成后重新启动
            handler.postDelayed({
                startSyncthing()
            }, 2000)
        }
    }
    
    /**
     * 重置 delta 索引
     */
    private fun resetDeltas() {
        Log.i(TAG, "Resetting Syncthing delta indexes")
        shutdown(State.INIT) {
            val resetRunnable = SyncthingRunnable(this, SyncthingRunnable.Command.RESET_DELTAS)
            Thread(resetRunnable).apply {
                name = "SyncthingResetDeltasThread"
                start()
            }
            // 重置完成后重新启动
            handler.postDelayed({
                startSyncthing()
            }, 2000)
        }
    }
    
    /**
     * 生成初始配置
     */
    private fun generateInitialConfig() {
        val generateRunnable = SyncthingRunnable(this, SyncthingRunnable.Command.GENERATE)
        Thread(generateRunnable).apply {
            name = "SyncthingGenerateThread"
            start()
        }
    }
    
    /**
     * 检查 Syncthing 状态
     */
    private fun checkSyncthingStatus() {
        // 这里可以添加检查 Syncthing REST API 是否可用的逻辑
        // 暂时简单地将状态设置为 ACTIVE
        if (currentState == State.STARTING) {
            Log.i(TAG, "Syncthing appears to be running")
            onServiceStateChange(State.ACTIVE)
        }
    }
    
    /**
     * 关闭 Syncthing
     */
    private fun shutdown(newState: State, onKilled: () -> Unit) {
        Log.i(TAG, "Shutting down Syncthing")
        
        syncthingRunnable?.killSyncthing()
        syncthingRunnable = null
        
        syncthingRunnableThread?.interrupt()
        syncthingRunnableThread = null
        
        // 停止 HTTPS API Controller
        stopHttpsApiController()
        
        onServiceStateChange(newState)
        onKilled()
    }
    
    /**
     * 注册服务状态变化监听器
     */
    fun registerOnServiceStateChangeListener(listener: OnServiceStateChangeListener) {
        onServiceStateChangeListeners.add(listener)
        // 立即通知当前状态
        listener.onServiceStateChange(currentState)
    }
    
    /**
     * 注销服务状态变化监听器
     */
    fun unregisterOnServiceStateChangeListener(listener: OnServiceStateChangeListener) {
        onServiceStateChangeListeners.remove(listener)
    }
    
    /**
     * 通知服务状态变化
     */
    private fun onServiceStateChange(newState: State) {
        currentState = newState
        Log.i(TAG, "Service state changed to: $newState")
        
        // 更新通知
        val notificationText = when (newState) {
            State.INIT -> "正在初始化..."
            State.STARTING -> "正在启动 Syncthing..."
            State.ACTIVE -> "Syncthing 运行中"
            State.DISABLED -> "Syncthing 已停止"
            State.ERROR -> "Syncthing 出错"
        }
        updateNotification(notificationText)
        
        // 在主线程中通知监听器
        handler.post {
            onServiceStateChangeListeners.forEach { listener ->
                listener.onServiceStateChange(newState)
            }
        }
    }
    
    /**
     * 获取当前状态
     */
    fun getCurrentState(): State {
        return currentState
    }
    
    /**
     * 启动 HTTPS API Controller
     */
    private fun startHttpsApiController() {
        if (httpsApiController == null) {
            httpsApiController = HttpsApiController(this)
            httpsApiController?.start()
            Log.i(TAG, "HTTPS API Controller started")
        }
    }
    
    /**
     * 停止 HTTPS API Controller
     */
    private fun stopHttpsApiController() {
        httpsApiController?.stop()
        httpsApiController = null
        Log.i(TAG, "HTTPS API Controller stopped")
    }
    
    /**
     * 获取 HTTPS API Controller 状态
     */
    fun isHttpsApiControllerRunning(): Boolean {
        return httpsApiController?.isRunning() ?: false
    }
    
    /**
     * 获取 API 服务器 URL
     */
    fun getApiServerUrl(): String {
        return httpsApiController?.getServerUrl() ?: "http://127.0.0.1:3434"
    }
    
    /**
     * 创建通知渠道
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Syncthing 服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "MyData 同步服务通知"
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
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MyData")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
    
    /**
     * 更新通知
     */
    private fun updateNotification(content: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification(content))
    }
} 