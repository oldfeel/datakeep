package site.datakeep.service

import android.content.Context
import android.os.Build
import android.os.Environment
import java.io.File
import java.util.concurrent.TimeUnit

object Constants {
    const val FILENAME_SYNCTHING_BINARY = "libsyncthing.so"
    
    // 服务状态
    const val ACTION_RESTART = "site.datakeep.service.SyncthingService.RESTART"
    const val ACTION_RESET_DATABASE = "site.datakeep.service.SyncthingService.RESET_DATABASE"
    const val ACTION_RESET_DELTAS = "site.datakeep.service.SyncthingService.RESET_DELTAS"
    
    // 配置相关
    const val CONFIG_FILE = "config.xml"
    const val CONFIG_TEMP_FILE = "config.xml.tmp"
    const val PUBLIC_KEY_FILE = "cert.pem"
    const val PRIVATE_KEY_FILE = "key.pem"
    const val HTTPS_CERT_FILE = "https-cert.pem"
    const val HTTPS_KEY_FILE = "https-key.pem"
    
    // GUI 更新间隔
    val GUI_UPDATE_INTERVAL = TimeUnit.SECONDS.toMillis(5)
    
    // 导出路径
    val EXPORT_PATH = File(Environment.getExternalStorageDirectory(), "backups/datakeep")
    
    fun getSyncthingBinary(context: Context): File {
        val nativeLibDir = context.applicationInfo.nativeLibraryDir
        val binaryFile = File(nativeLibDir, FILENAME_SYNCTHING_BINARY)
        
        // 详细的调试信息
        android.util.Log.i("Constants", "🔍 获取 Syncthing 二进制文件信息")
        android.util.Log.i("Constants", "📁 原生库目录: $nativeLibDir")
        android.util.Log.i("Constants", "📄 二进制文件路径: ${binaryFile.absolutePath}")
        android.util.Log.i("Constants", "✅ 文件存在: ${binaryFile.exists()}")
        
        if (binaryFile.exists()) {
            android.util.Log.i("Constants", "📊 文件大小: ${binaryFile.length()} 字节")
            android.util.Log.i("Constants", "🔐 文件权限: ${binaryFile.canRead()}, ${binaryFile.canWrite()}, ${binaryFile.canExecute()}")
            android.util.Log.i("Constants", "📖 可读: ${binaryFile.canRead()}")
            android.util.Log.i("Constants", "⚡ 可执行: ${binaryFile.canExecute()}")
            
            // 检查文件类型
            try {
                val firstBytes = ByteArray(4)
                val bytesRead = binaryFile.inputStream().use { input ->
                    input.read(firstBytes, 0, 4)
                }
                val isElf = bytesRead >= 4 && firstBytes[0] == 0x7F.toByte() && 
                           firstBytes[1] == 0x45.toByte() && firstBytes[2] == 0x4C.toByte() && 
                           firstBytes[3] == 0x46.toByte()
                android.util.Log.i("Constants", "🔍 文件类型: ${if (isElf) "ELF 二进制文件" else "未知文件类型"}")
            } catch (e: Exception) {
                android.util.Log.w("Constants", "⚠️ 无法检查文件类型", e)
            }
        } else {
            android.util.Log.e("Constants", "❌ 二进制文件不存在！")
            android.util.Log.e("Constants", "📁 请检查 jniLibs 目录配置")
            android.util.Log.e("Constants", "📋 期望路径: ${binaryFile.absolutePath}")
        }
        
        return binaryFile
    }
    
    fun getLogFile(context: Context): File {
        return File(context.getExternalFilesDir(null), "syncthing.log")
    }
    
    fun getConfigFile(context: Context): File {
        return File(context.filesDir, CONFIG_FILE)
    }
    
    fun getConfigTempFile(context: Context): File {
        return File(context.filesDir, CONFIG_TEMP_FILE)
    }
    
    fun getPublicKeyFile(context: Context): File {
        return File(context.filesDir, PUBLIC_KEY_FILE)
    }
    
    fun getPrivateKeyFile(context: Context): File {
        return File(context.filesDir, PRIVATE_KEY_FILE)
    }
    
    fun getHttpsCertFile(context: Context): File {
        return File(context.filesDir, HTTPS_CERT_FILE)
    }
    
    fun getHttpsKeyFile(context: Context): File {
        return File(context.filesDir, HTTPS_KEY_FILE)
    }
    
    fun osSupportsTLS12(): Boolean {
        return if (Build.VERSION.SDK_INT == Build.VERSION_CODES.N) {
            // Android N/7.0 有 SSL 问题，不支持 TLS 1.2
            false
        } else {
            true
        }
    }
} 