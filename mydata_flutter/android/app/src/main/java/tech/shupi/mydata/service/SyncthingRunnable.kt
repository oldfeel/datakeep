package tech.shupi.mydata.service

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

        /** 清理残留 Syncthing 进程，避免数据库锁导致 exit 1 */
        fun killOrphanProcesses() {
            try {
                Runtime.getRuntime().exec(arrayOf("pkill", "-9", "-f", "libsyncthing.so")).waitFor()
                Thread.sleep(300)
            } catch (e: Exception) {
                Log.w(TAG, "killOrphanProcesses failed", e)
            }
        }
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
                syncthingBinary.path, "-home", homeDir, "-no-browser", "-no-restart", "-no-upgrade", "-logflags=0"
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
        Log.i(TAG, "🚀 开始启动 Syncthing 原生二进制文件")
        Log.i(TAG, "📁 二进制文件路径: ${syncthingBinary.absolutePath}")
        Log.i(TAG, "🔧 命令类型: $command")
        Log.i(TAG, "📋 完整命令: ${commandArray.joinToString(" ")}")
        
        trimLogFile()
        var capturedStdOut = ""
        
        // 检查文件是否存在
        if (!syncthingBinary.exists()) {
            Log.e(TAG, "❌ Syncthing 二进制文件不存在: ${syncthingBinary.absolutePath}")
            Log.e(TAG, "📁 请检查 jniLibs 目录是否正确配置")
            return ""
        }
        
        Log.i(TAG, "✅ Syncthing 二进制文件存在")
        Log.i(TAG, "📊 文件大小: ${syncthingBinary.length()} 字节")
        Log.i(TAG, "🔐 文件权限: 读=${syncthingBinary.canRead()}, 写=${syncthingBinary.canWrite()}, 执行=${syncthingBinary.canExecute()}")
        
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

            if (command == Command.MAIN) {
                ConfigHelper.ensureConfigExists(context)
                ConfigHelper.ensureLocalDeviceName(context)
            }
            
            val targetEnv = buildEnvironment()
            Log.i(TAG, "🌍 环境变量设置完成，准备启动进程...")
            Log.i(TAG, "🔧 关键环境变量:")
            Log.i(TAG, "  - GO111MODULE: ${targetEnv["GO111MODULE"]}")
            Log.i(TAG, "  - CGO_ENABLED: ${targetEnv["CGO_ENABLED"]}")
            Log.i(TAG, "  - SYNCTHING_ANDROID: ${targetEnv["SYNCTHING_ANDROID"]}")
            
            process = setupAndLaunch(targetEnv)
            syncthingProcess.set(process)
            
            Log.i(TAG, "✅ Syncthing 进程启动成功")
            try {
                val pidField = process.javaClass.getDeclaredField("pid")
                pidField.isAccessible = true
                val pid = pidField.getInt(process)
                Log.i(TAG, "🆔 进程 ID: $pid")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ 无法获取进程 ID", e)
                Log.i(TAG, "🆔 进程 ID: 未知")
            }
            Log.i(TAG, "📊 进程存活状态: ${process.isAlive}")
            
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
                    Log.w(TAG, "Another Syncthing instance is already running, scheduling restart")
                    scheduleRestart()
                }
                3 -> {
                    Log.i(TAG, "Restarting syncthing")
                    scheduleRestart()
                }
                141, 143 -> {
                    Log.w(TAG, "Syncthing killed (exit $ret), scheduling restart")
                    scheduleRestart()
                }
                else -> {
                    Log.w(TAG, "Syncthing has crashed (exit code $ret), scheduling restart")
                    scheduleRestart()
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
    
    private fun scheduleRestart() {
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            context.startService(
                Intent(context, SyncthingService::class.java)
                    .setAction(SyncthingService.ACTION_RESTART),
            )
        }, 3000)
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
        Log.i(TAG, "🔧 创建 ProcessBuilder...")
        Log.i(TAG, "📋 命令数组: ${commandArray.joinToString(" ")}")
        Log.i(TAG, "🌍 环境变量数量: ${env.size}")
        
        val pb = ProcessBuilder(*commandArray)
        pb.environment().putAll(env)
        pb.redirectErrorStream(false)
        
        Log.i(TAG, "🚀 启动进程...")
        val process = pb.start()
        Log.i(TAG, "✅ 进程启动完成")
        
        return process
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