package com.mydata.app.service

import android.content.Context
import android.os.Build
import android.os.Environment
import java.io.File
import java.util.concurrent.TimeUnit

object Constants {
    const val FILENAME_SYNCTHING_BINARY = "libsyncthing.so"
    
    // 服务状态
    const val ACTION_RESTART = "com.mydata.app.service.SyncthingService.RESTART"
    const val ACTION_RESET_DATABASE = "com.mydata.app.service.SyncthingService.RESET_DATABASE"
    const val ACTION_RESET_DELTAS = "com.mydata.app.service.SyncthingService.RESET_DELTAS"
    
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
    val EXPORT_PATH = File(Environment.getExternalStorageDirectory(), "backups/mydata")
    
    fun getSyncthingBinary(context: Context): File {
        val nativeLibDir = context.applicationInfo.nativeLibraryDir
        val binaryFile = File(nativeLibDir, FILENAME_SYNCTHING_BINARY)
        
        // 调试信息
        android.util.Log.d("Constants", "Native library dir: $nativeLibDir")
        android.util.Log.d("Constants", "Binary file path: ${binaryFile.absolutePath}")
        android.util.Log.d("Constants", "Binary file exists: ${binaryFile.exists()}")
        android.util.Log.d("Constants", "Binary file can read: ${binaryFile.canRead()}")
        android.util.Log.d("Constants", "Binary file can execute: ${binaryFile.canExecute()}")
        
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