package tech.shupi.mydata.service

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import mobile.API
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.*

/**
 * BackendService 使用 gomobile 编译的 Go backend
 * 统一管理 Syncthing 和 HTTPS API 服务器
 */
class BackendService(private val context: Context) {
    
    companion object {
        private const val TAG = "BackendService"
    }
    
    private val api: API = API()
    private var initialized = false
    
    /**
     * 获取本机局域网 IP 地址列表
     */
    private fun getLocalNetworkIPs(): List<String> {
        val localIPs = mutableListOf<String>()
        
        try {
            // 方法1: 通过 WifiManager 获取（需要权限，但更可靠）
            try {
                val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                wifiManager?.let {
                    val wifiInfo = it.connectionInfo
                    val ipAddress = wifiInfo.ipAddress
                    if (ipAddress != 0) {
                        val ip = String.format(
                            Locale.getDefault(),
                            "%d.%d.%d.%d",
                            ipAddress and 0xff,
                            ipAddress shr 8 and 0xff,
                            ipAddress shr 16 and 0xff,
                            ipAddress shr 24 and 0xff
                        )
                        localIPs.add(ip)
                        Log.d(TAG, "通过 WifiManager 获取到 IP: $ip")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "通过 WifiManager 获取 IP 失败: ${e.message}")
            }
            
            // 方法2: 通过 NetworkInterface 获取所有网络接口的 IP
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                // 跳过回环接口和未启用的接口
                if (intf.isLoopback || !intf.isUp) {
                    continue
                }
                
                val addrs = Collections.list(intf.inetAddresses)
                for (addr in addrs) {
                    // 只获取 IPv4 地址，并且是私有地址
                    if (addr is InetAddress && !addr.isLoopbackAddress) {
                        val hostAddress = addr.hostAddress
                        if (hostAddress != null && isPrivateIP(hostAddress)) {
                            if (!localIPs.contains(hostAddress)) {
                                localIPs.add(hostAddress)
                                Log.d(TAG, "通过 NetworkInterface 获取到 IP: $hostAddress")
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "获取本机 IP 地址失败", e)
        }
        
        return localIPs
    }
    
    /**
     * 判断是否为私有 IP 地址
     */
    private fun isPrivateIP(ip: String): Boolean {
        return ip.startsWith("192.168.") ||
                ip.startsWith("10.") ||
                ip.startsWith("172.16.") ||
                ip.startsWith("172.17.") ||
                ip.startsWith("172.18.") ||
                ip.startsWith("172.19.") ||
                ip.startsWith("172.20.") ||
                ip.startsWith("172.21.") ||
                ip.startsWith("172.22.") ||
                ip.startsWith("172.23.") ||
                ip.startsWith("172.24.") ||
                ip.startsWith("172.25.") ||
                ip.startsWith("172.26.") ||
                ip.startsWith("172.27.") ||
                ip.startsWith("172.28.") ||
                ip.startsWith("172.29.") ||
                ip.startsWith("172.30.") ||
                ip.startsWith("172.31.")
    }
    
    /**
     * 初始化 backend（设置路径等）
     */
    fun initialize() {
        if (initialized) {
            Log.w(TAG, "Backend 已经初始化")
            return
        }
        
        try {
            // 1. 设置 Syncthing 路径
            val syncthingPath = Constants.getSyncthingBinary(context).absolutePath
            Log.i(TAG, "设置 Syncthing 路径: $syncthingPath")
            api.setSyncthingPath(syncthingPath)
            
            // 2. 设置数据目录（用于数据库、证书等）
            val dataDir = context.filesDir.absolutePath
            Log.i(TAG, "设置数据目录: $dataDir")
            api.setDataDir(dataDir)
            
            // 3. 获取并设置本机局域网 IP 地址（避免 Go 代码的权限问题）
            val localIPs = getLocalNetworkIPs()
            if (localIPs.isNotEmpty()) {
                Log.i(TAG, "设置本机局域网 IP: $localIPs")
                // 将 IP 列表用逗号连接成字符串传递（gomobile 不支持 []string 参数）
                val ipsString = localIPs.joinToString(",")
                api.setLocalNetworkIPs(ipsString)
            } else {
                Log.w(TAG, "⚠️ 未获取到本机局域网 IP")
            }
            
            initialized = true
            Log.i(TAG, "✅ Backend 初始化完成")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Backend 初始化失败", e)
            throw e
        }
    }
    
    /**
     * 启动服务（包括 Syncthing 和 HTTPS 服务器）
     */
    fun start(): String {
        if (!initialized) {
            initialize()
        }
        
        try {
            // 1. 启动 Syncthing
            Log.i(TAG, "🚀 启动 Syncthing...")
            val syncthingError = api.startSyncthing()
            if (syncthingError.isNotEmpty()) {
                Log.e(TAG, "启动 Syncthing 失败: $syncthingError")
                return "启动 Syncthing 失败: $syncthingError"
            }
            Log.i(TAG, "✅ Syncthing 启动成功")
            
            // 等待 Syncthing 就绪（可选）
            Thread.sleep(2000)
            
            // 2. 启动 HTTPS API 服务器
            Log.i(TAG, "🚀 启动 HTTPS API 服务器...")
            val serverError = api.startServer()
            if (serverError.isNotEmpty()) {
                Log.e(TAG, "启动服务器失败: $serverError")
                // 如果服务器启动失败，停止 Syncthing
                api.stopSyncthing()
                return "启动服务器失败: $serverError"
            }
            Log.i(TAG, "✅ HTTPS API 服务器启动成功")
            Log.i(TAG, "📡 服务器地址: ${api.getServerURL()}")
            
            return ""
        } catch (e: Exception) {
            Log.e(TAG, "❌ 启动服务失败", e)
            return "启动服务失败: ${e.message}"
        }
    }
    
    /**
     * 停止服务
     */
    fun stop(): String {
        try {
            val errors = mutableListOf<String>()
            
            // 停止 HTTPS 服务器
            val serverError = api.stopServer()
            if (serverError.isNotEmpty()) {
                errors.add("停止服务器失败: $serverError")
            }
            
            // 停止 Syncthing
            val syncthingError = api.stopSyncthing()
            if (syncthingError.isNotEmpty()) {
                errors.add("停止 Syncthing 失败: $syncthingError")
            }
            
            if (errors.isEmpty()) {
                Log.i(TAG, "✅ 服务停止成功")
                return ""
            } else {
                val errorMsg = errors.joinToString("; ")
                Log.e(TAG, "❌ 停止服务时出错: $errorMsg")
                return errorMsg
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ 停止服务失败", e)
            return "停止服务失败: ${e.message}"
        }
    }
    
    /**
     * 检查服务状态
     */
    fun isRunning(): Boolean {
        return api.isServerRunning() && api.isSyncthingRunning()
    }
    
    /**
     * 获取服务器 URL
     */
    fun getServerURL(): String {
        return api.getServerURL()
    }
}

