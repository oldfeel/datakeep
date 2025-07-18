package com.mydata.app.service

import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log
import java.io.*
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicReference

/**
 * 运行 syncthing 原生二进制文件，并将其输出打印到 logcat
 */
class SyncthingRunnable(private val context: Context, private val command: Command) : Runnable {
    
    companion object {
        private const val TAG = "SyncthingRunnable"
        private const val TAG_NATIVE = "SyncthingNativeCode"
        private const val LOG_FILE_MAX_LINES = 10
        
        private val syncthingProcess = AtomicReference<Process>()
    }
    
    enum class Command {
        DEVICE_ID,      // 输出设备 ID 到命令行
        GENERATE,       // 生成密钥和配置文件并立即退出
        MAIN,           // 运行主 Syncthing 应用程序
        RESET_DATABASE, // 重置 Syncthing 数据库
        RESET_DELTAS    // 重置 Syncthing 的 delta 索引
    }
    
    private val syncthingBinary: File = Constants.getSyncthingBinary(context)
    private val logFile: File = Constants.getLogFile(context)
    private lateinit var commandArray: Array<String>
    
    init {
        setupCommand()
    }
    
    private fun setupCommand() {
        val homeDir = context.filesDir.toString()
        commandArray = when (command) {
            Command.DEVICE_ID -> arrayOf(
                syncthingBinary.path, "-home", homeDir, "--device-id"
            )
            Command.GENERATE -> arrayOf(
                syncthingBinary.path, "-generate", homeDir, "-logflags=0"
            )
            Command.MAIN -> arrayOf(
                syncthingBinary.path, "-home", homeDir, "-no-browser", "-logflags=0"
            )
            Command.RESET_DATABASE -> arrayOf(
                syncthingBinary.path, "-home", homeDir, "-reset-database", "-logflags=0"
            )
            Command.RESET_DELTAS -> arrayOf(
                syncthingBinary.path, "-home", homeDir, "-reset-deltas", "-logflags=0"
            )
        }
    }
    
    override fun run() {
        run(false)
    }
    
    fun run(returnStdOut: Boolean): String {
        trimLogFile()
        var capturedStdOut = ""
        
        // 检查文件是否存在
        if (!syncthingBinary.exists()) {
            Log.e(TAG, "Syncthing binary not found at: ${syncthingBinary.absolutePath}")
            return ""
        }
        
        // 确保 Syncthing 可执行
        try {
            val pb = ProcessBuilder("chmod", "755", syncthingBinary.path)
            val p = pb.start()
            val result = p.waitFor()
            Log.d(TAG, "chmod result: $result")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to chmod Syncthing", e)
        }
        
        // 循环运行 Syncthing
        var process: Process? = null
        
        // 保持 CPU 运行，防止原生二进制文件运行时被休眠
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MyData:SyncthingRunnable"
        )
        
        try {
            wakeLock.acquire()
            increaseInotifyWatches()
            
            val targetEnv = buildEnvironment()
            process = setupAndLaunch(targetEnv)
            syncthingProcess.set(process)
            
            var lInfo: Thread? = null
            var lWarn: Thread? = null
            
            if (returnStdOut) {
                val br = BufferedReader(InputStreamReader(process.inputStream, StandardCharsets.UTF_8))
                try {
                    var line: String?
                    while (br.readLine().also { line = it } != null) {
                        line?.let { nonNullLine ->
                            Log.println(Log.INFO, TAG_NATIVE, nonNullLine)
                            capturedStdOut += nonNullLine + "\n"
                        }
                    }
                } finally {
                    br.close()
                }
            } else {
                lInfo = log(process.inputStream, Log.INFO, true)
                lWarn = log(process.errorStream, Log.WARN, true)
            }
            
            niceSyncthing()
            
            val ret = process.waitFor()
            Log.i(TAG, "Syncthing exited with code $ret")
            syncthingProcess.set(null)
            
            lInfo?.join()
            lWarn?.join()
            
            when (ret) {
                0, 137 -> {
                    // Syncthing 正常关闭（通过 API 或 SIGKILL），无需操作
                }
                1 -> {
                    Log.w(TAG, "Another Syncthing instance is already running, requesting restart")
                    // 继续执行
                }
                3 -> {
                    // 通过 REST API 请求重启
                    Log.i(TAG, "Restarting syncthing")
                    context.startService(Intent(context, SyncthingService::class.java)
                        .setAction(Constants.ACTION_RESTART))
                }
                else -> {
                    Log.w(TAG, "Syncthing has crashed (exit code $ret)")
                    // 可以在这里显示崩溃通知
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to execute syncthing binary or read output", e)
        } finally {
            wakeLock.release()
            process?.destroy()
        }
        
        return capturedStdOut
    }
    
    fun killSyncthing() {
        val process = syncthingProcess.get()
        if (process != null) {
            try {
                process.destroy()
                // 等待进程结束
                if (!process.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                }
            } catch (e: InterruptedException) {
                Log.w(TAG, "Interrupted while waiting for syncthing to stop", e)
            }
        }
    }
    
    private fun trimLogFile() {
        if (!logFile.exists()) return
        
        try {
            val lines = logFile.readLines()
            if (lines.size > LOG_FILE_MAX_LINES) {
                val trimmedLines = lines.takeLast(LOG_FILE_MAX_LINES)
                logFile.writeText(trimmedLines.joinToString("\n"))
            }
        } catch (e: IOException) {
            Log.w(TAG, "Failed to trim log file", e)
        }
    }
    
    private fun buildEnvironment(): HashMap<String, String> {
        val env = HashMap<String, String>()
        env.putAll(System.getenv())
        
        // 设置 Syncthing 环境变量
        env["GO111MODULE"] = "on"
        env["CGO_ENABLED"] = "1"
        env["SYNCTHING_ANDROID"] = "1"
        
        return env
    }
    
    private fun setupAndLaunch(env: HashMap<String, String>): Process {
        val pb = ProcessBuilder(*commandArray)
        pb.environment().putAll(env)
        pb.redirectErrorStream(false)
        return pb.start()
    }
    
    private fun increaseInotifyWatches() {
        try {
            val pb = ProcessBuilder("echo", "1048576", ">", "/proc/sys/fs/inotify/max_user_watches")
            pb.start()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to increase inotify watches", e)
        }
    }
    
    private fun niceSyncthing() {
        try {
            val process = syncthingProcess.get()
            if (process != null) {
                // 使用反射获取进程 ID，兼容较老的 Android 版本
                val pidField = process.javaClass.getDeclaredField("pid")
                pidField.isAccessible = true
                val pid = pidField.getInt(process)
                
                val pb = ProcessBuilder("renice", "-n", "10", "-p", pid.toString())
                pb.start()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to nice syncthing", e)
        }
    }
    
    private fun log(inputStream: InputStream, priority: Int, saveLog: Boolean): Thread {
        return Thread {
            val reader = BufferedReader(InputStreamReader(inputStream, StandardCharsets.UTF_8))
            try {
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    line?.let { nonNullLine ->
                        Log.println(priority, TAG_NATIVE, nonNullLine)
                        if (saveLog) {
                            appendToLogFile(nonNullLine)
                        }
                    }
                }
            } catch (e: IOException) {
                Log.w(TAG, "Failed to read syncthing output", e)
            } finally {
                reader.close()
            }
        }.apply { start() }
    }
    
    private fun appendToLogFile(line: String) {
        try {
            logFile.appendText("$line\n")
        } catch (e: IOException) {
            Log.w(TAG, "Failed to append to log file", e)
        }
    }
    
    interface OnSyncthingKilled {
        fun onKilled()
    }
} 