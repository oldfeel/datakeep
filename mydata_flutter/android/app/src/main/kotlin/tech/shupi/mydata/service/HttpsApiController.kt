package tech.shupi.mydata.service

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import java.io.*
import java.net.ServerSocket
import java.net.Socket
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.net.ssl.*
import java.security.SecureRandom
import java.security.KeyManagementException
import java.security.NoSuchAlgorithmException
import java.security.PrivateKey
import java.security.KeyFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64
import java.net.NetworkInterface
import java.net.Inet4Address

/**
 * HTTPS API 服务器，提供与桌面版相同的 REST API 接口
 * 使用预制证书实现 HTTPS，直接访问 Syncthing REST API
 */
class HttpsApiController(private val context: Context) {
    
    companion object {
        private const val TAG = "HttpsApiController"
        private const val PORT = 8443 // 使用 HTTPS 端口
        private const val SYNCTHING_PORT = 8384 // Syncthing 默认端口
    }
    
    // Syncthing API 配置 - 尝试从桌面端获取数据
    private val syncthingApiBase = "http://127.0.0.1:8384" // 本地 Syncthing 地址
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    
    // API Key 延迟初始化，避免构造函数失败
    private var _apiKey: String? = null
    private val apiKey: String
        get() {
            if (_apiKey == null) {
                _apiKey = getApiKeyFromConfig()
            }
            return _apiKey!!
        }
    
    private val gson = Gson()
    private var httpClient: OkHttpClient? = null
    private var serverSocket: SSLServerSocket? = null
    private var executor: ExecutorService? = null
    private var running = false
    
    /**
     * 启动 HTTPS 服务器
     */
    fun start() {
        Log.d(TAG, "开始启动 HTTPS API 服务器...")
        
        if (running) {
            Log.w(TAG, "HTTPS 服务器已经在运行")
            return
        }
        
        try {
            Log.i(TAG, "正在启动 HTTPS API 服务器，端口: $PORT")
            Log.d(TAG, "服务器将监听所有网络接口")
            
            // 创建线程池
            Log.d(TAG, "创建线程池...")
            executor = Executors.newCachedThreadPool()
            Log.d(TAG, "线程池创建成功")
            
            // 创建 SSL 服务器套接字
            Log.d(TAG, "创建 SSL 服务器套接字...")
            serverSocket = createSslServerSocket(PORT)
            Log.d(TAG, "SSL 服务器套接字创建成功，绑定端口: $PORT")
            
            // 获取服务器地址信息
            val serverAddress = serverSocket?.inetAddress
            val serverPort = serverSocket?.localPort
            Log.i(TAG, "服务器绑定地址: ${serverAddress?.hostAddress ?: "0.0.0.0"}, 端口: $serverPort")
            
            running = true
            Log.d(TAG, "服务器状态设置为运行中")
            
            // 启动监听线程
            Log.d(TAG, "启动监听线程...")
            executor?.submit {
                Log.i(TAG, "监听线程已启动，等待客户端连接...")
                while (running) {
                    try {
                        Log.d(TAG, "等待客户端连接...")
                        val clientSocket = serverSocket?.accept()
                        if (clientSocket != null) {
                            val clientAddress = clientSocket.inetAddress.hostAddress
                            val clientPort = clientSocket.port
                            Log.i(TAG, "收到客户端连接: $clientAddress:$clientPort")
                            executor?.submit { handleClient(clientSocket) }
                        }
                    } catch (e: Exception) {
                        if (running) {
                            Log.e(TAG, "处理客户端连接失败", e)
                        } else {
                            Log.d(TAG, "服务器已停止，退出监听循环")
                        }
                    }
                }
                Log.d(TAG, "监听线程已退出")
            }
            
            Log.i(TAG, "✅ HTTP API 服务器启动成功！")
            Log.i(TAG, "📡 服务器地址: http://0.0.0.0:$PORT")
            Log.i(TAG, "🌐 局域网访问: http://127.0.0.1:$PORT")
            Log.i(TAG, "📋 可用的 API 端点:")
            Log.i(TAG, "  - GET  /api/devices")
            Log.i(TAG, "  - GET  /api/device/{deviceId}/folders")
            Log.i(TAG, "  - GET  /api/folder/{folderId}")
            Log.i(TAG, "  - GET  /api/local-device-id")
            Log.i(TAG, "  - GET  /api/wifi-info")
            Log.i(TAG, "  - POST /api/folder/{folderId}/share")
            Log.i(TAG, "  - GET  /api/syncthing/events")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 启动 HTTPS 服务器失败", e)
            Log.e(TAG, "错误详情: ${e.message}")
            Log.e(TAG, "可能的原因:")
            Log.e(TAG, "  - 端口 $PORT 已被占用")
            Log.e(TAG, "  - 权限不足")
            Log.e(TAG, "  - 网络配置问题")
            throw e
        }
    }
    
    /**
     * 创建 SSL 服务器套接字
     */
    private fun createSslServerSocket(port: Int): SSLServerSocket {
        Log.i(TAG, "开始创建 SSL 服务器套接字，端口: $port")
        
        try {
            // 1. 加载预制证书
            Log.i(TAG, "正在加载预制证书...")
            val cert = loadCertificate()
            if (cert == null) {
                throw Exception("预制证书加载失败")
            }
            Log.i(TAG, "预制证书加载成功")
            
            // 2. 加载预制私钥
            Log.i(TAG, "正在加载预制私钥...")
            val privateKey = loadPrivateKey()
            if (privateKey == null) {
                throw Exception("预制私钥加载失败")
            }
            Log.i(TAG, "预制私钥加载成功")
            
            // 3. 创建 KeyStore
            Log.i(TAG, "正在创建 KeyStore...")
            val keyStore = KeyStore.getInstance("PKCS12")
            keyStore.load(null, null)
            keyStore.setKeyEntry("alias", privateKey, "password".toCharArray(), arrayOf(cert))
            Log.i(TAG, "KeyStore 创建成功")
            
            // 4. 创建 KeyManager
            Log.i(TAG, "正在创建 KeyManager...")
            val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
            kmf.init(keyStore, "password".toCharArray())
            Log.i(TAG, "KeyManager 创建成功")
            
            // 5. 创建 SSLContext
            Log.i(TAG, "正在创建 SSLContext...")
            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(kmf.keyManagers, null, null)
            Log.i(TAG, "SSLContext 创建成功")
            
            // 6. 创建 SSLServerSocket
            Log.i(TAG, "正在创建 SSLServerSocket...")
            val ssf = sslContext.serverSocketFactory
            val serverSocket = ssf.createServerSocket(port) as SSLServerSocket
            serverSocket.enabledProtocols = arrayOf("TLSv1.2")
            Log.i(TAG, "SSLServerSocket 创建成功")
            
            return serverSocket
        } catch (e: Exception) {
            Log.e(TAG, "创建 SSL 服务器套接字失败", e)
            throw e
        }
    }
    
    /**
     * 加载预制证书
     */
    private fun loadCertificate(): X509Certificate? {
        return try {
            val certStream = context.assets.open("certificate.crt")
            val certFactory = CertificateFactory.getInstance("X.509")
            val cert = certFactory.generateCertificate(certStream) as X509Certificate
            certStream.close()
            Log.i(TAG, "预制证书加载成功")
            cert
        } catch (e: Exception) {
            Log.e(TAG, "加载预制证书失败", e)
            null
        }
    }
    
    /**
     * 加载预制私钥
     */
    private fun loadPrivateKey(): PrivateKey? {
        return try {
            val keyStream = context.assets.open("private.key")
            val keyBytes = ByteArray(keyStream.available())
            keyStream.read(keyBytes)
            keyStream.close()
            
            // 解析 PEM 格式的私钥
            val pemKey = String(keyBytes)
            
            // 移除 PEM 头尾和换行符
            val privateKeyPEM = pemKey
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replace("\\s".toRegex(), "")
            
            // Base64 解码
            val decodedKey = Base64.getDecoder().decode(privateKeyPEM)
            
            // 解析 PKCS8 格式的私钥
            val keySpec = PKCS8EncodedKeySpec(decodedKey)
            val keyFactory = KeyFactory.getInstance("RSA")
            val privateKey = keyFactory.generatePrivate(keySpec)
            
            Log.i(TAG, "预制私钥加载成功")
            privateKey
        } catch (e: Exception) {
            Log.e(TAG, "加载预制私钥失败", e)
            null
        }
    }
    
    /**
     * 停止 HTTPS 服务器
     */
    fun stop() {
        Log.i(TAG, "停止 HTTPS API 服务器")
        running = false
        
        try {
            serverSocket?.close()
            executor?.shutdown()
            executor?.awaitTermination(5, TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.e(TAG, "停止服务器失败", e)
        } finally {
            serverSocket = null
            executor = null
        }
    }
    
    /**
     * 处理客户端连接
     */
    private fun handleClient(clientSocket: Socket) {
        val clientAddress = clientSocket.inetAddress.hostAddress
        val clientPort = clientSocket.port
        Log.d(TAG, "🔗 开始处理客户端连接: $clientAddress:$clientPort")
        
        try {
            val input = BufferedReader(InputStreamReader(clientSocket.getInputStream()))
            val output = clientSocket.getOutputStream()
            
            // 读取请求行
            Log.d(TAG, "📖 读取请求行...")
            val requestLine = input.readLine()
            if (requestLine == null) {
                Log.w(TAG, "❌ 请求行为空")
                sendErrorResponse(output, 400, "Bad Request")
                return
            }
            
            Log.d(TAG, "📝 请求行: $requestLine")
            val parts = requestLine.split(" ")
            if (parts.size < 3) {
                Log.w(TAG, "❌ 请求行格式错误: $requestLine")
                sendErrorResponse(output, 400, "Bad Request")
                return
            }
            
            val method = parts[0]
            val uri = parts[1]
            Log.d(TAG, "🔍 解析请求: 方法=$method, URI=$uri")
            
            // 读取请求头
            Log.d(TAG, "📋 读取请求头...")
            val headers = mutableMapOf<String, String>()
            var line: String?
            while (input.readLine().also { line = it } != null && line?.isNotEmpty() == true) {
                val headerParts = line?.split(": ", limit = 2)
                if (headerParts?.size == 2) {
                    headers[headerParts[0]] = headerParts[1]
                    Log.d(TAG, "📋 请求头: ${headerParts[0]} = ${headerParts[1]}")
                }
            }
            Log.d(TAG, "📋 请求头读取完成，共 ${headers.size} 个")
            
            // 处理请求
            Log.d(TAG, "⚙️ 开始处理请求...")
            val response = handleRequest(method, uri, headers)
            
            // 发送响应
            Log.d(TAG, "📤 发送响应...")
            val responseBytes = response.toByteArray(Charsets.UTF_8)
            val httpResponse = """
                HTTP/1.1 200 OK
                Content-Type: application/json; charset=utf-8
                Access-Control-Allow-Origin: *
                Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
                Access-Control-Allow-Headers: Content-Type, Authorization
                Content-Length: ${responseBytes.size}
                Connection: close
                
            """.trimIndent() + "\r\n"
            
            output.write(httpResponse.toByteArray(Charsets.UTF_8))
            output.write(responseBytes)
            output.flush()
            Log.i(TAG, "✅ 响应发送成功，长度: ${responseBytes.size} 字节")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 处理客户端请求失败", e)
            Log.e(TAG, "客户端地址: $clientAddress:$clientPort")
        } finally {
            try {
                clientSocket.close()
                Log.d(TAG, "🔌 客户端连接已关闭: $clientAddress:$clientPort")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 关闭客户端连接失败", e)
            }
        }
    }
    
    /**
     * 处理 HTTP 请求
     */
    private fun handleRequest(method: String, uri: String, headers: Map<String, String>): String {
        Log.i(TAG, "📥 收到请求: $method $uri")
        Log.d(TAG, "请求头: $headers")
        
        val response = when {
            uri.startsWith("/api/devices") -> {
                Log.d(TAG, "处理设备列表请求")
                handleDevices()
            }
            uri.startsWith("/api/device/") && uri.contains("/folders") -> {
                Log.d(TAG, "处理设备文件夹请求")
                handleDeviceFolders(uri)
            }
            uri.startsWith("/api/folder/") && uri.endsWith("/files") -> {
                Log.d(TAG, "处理文件夹文件请求")
                handleFolderFiles(uri)
            }
            uri == "/api/local-device-id" -> {
                Log.d(TAG, "处理本地设备ID请求")
                handleLocalDeviceId()
            }
            uri == "/api/wifi-info" -> {
                Log.d(TAG, "处理WiFi信息请求")
                handleWifiInfo()
            }
            uri.startsWith("/api/folder/") && uri.endsWith("/share") -> {
                Log.d(TAG, "处理文件夹共享请求")
                handleFolderShare(uri)
            }
            uri == "/api/syncthing/events" -> {
                Log.d(TAG, "处理Syncthing事件请求")
                handleSyncthingEvents()
            }
            uri == "/api/syncthing/discovery" -> {
                Log.d(TAG, "处理Syncthing设备发现请求")
                handleSyncthingDiscovery()
            }
            else -> {
                Log.w(TAG, "❌ 未找到匹配的路由: $method $uri")
                fail(404, "Not Found")
            }
        }
        
        Log.d(TAG, "📤 响应长度: ${response.length} 字符")
        return response
    }
    
    /**
     * 处理设备列表请求
     */
    private fun handleDevices(): String {
        return try {
            val devices = getDevicesFromSyncthing()
            success(devices)
        } catch (e: Exception) {
            Log.e(TAG, "获取设备列表失败", e)
            // 返回错误信息
            fail(500, "获取设备列表失败: ${e.message}")
        }
    }
    
    /**
     * 从 Syncthing API 获取设备列表
     * 使用与 Go 后端相同的接口: /rest/config/devices
     */
    private fun getDevicesFromSyncthing(): List<Map<String, Any>> {
        Log.d(TAG, "=== getDevicesFromSyncthing 开始 ===")
        
        try {
            // 获取设备配置 - 使用与 Go 后端相同的接口
            Log.d(TAG, "正在调用 Syncthing API: GET /rest/config/devices")
            val response = executeGetRequest("/rest/config/devices")
            Log.d(TAG, "API 响应长度: ${response.length} 字符")
            
            val jsonArray = JsonParser.parseString(response).asJsonArray
            Log.d(TAG, "成功解析到 ${jsonArray.size()} 个设备")
            
            val devices = mutableListOf<Map<String, Any>>()
            
            // 获取本机设备ID
            val localDeviceId = getLocalDeviceID()
            Log.d(TAG, "本机设备ID: $localDeviceId")
            
            // 解析设备列表
            for (i in 0 until jsonArray.size()) {
                val device = jsonArray[i].asJsonObject
                val deviceId = device.get("deviceID")?.asString ?: ""
                val deviceName = device.get("name")?.asString ?: "Unknown Device"
                
                Log.d(TAG, "  [${i + 1}] DeviceID: $deviceId, Name: $deviceName")
                
                // 检查是否为本机设备
                val isLocalDevice = localDeviceId.isNotEmpty() && deviceId == localDeviceId
                
                // 获取设备连接状态
                val connectionInfo = getDeviceConnectionInfo(deviceId)
                val isConnected = connectionInfo["connected"] as? Boolean ?: false
                val connectionType = connectionInfo["type"] as? String ?: "unknown"
                val clientVersion = connectionInfo["clientVersion"] as? String ?: ""
                
                // 获取设备地址
                val addresses = getDeviceAddresses(deviceId, isLocalDevice)
                
                val deviceMap = mapOf(
                    "id" to deviceId,
                    "name" to deviceName,
                    "address" to (addresses.firstOrNull() ?: "127.0.0.1"),
                    "addresses" to addresses,
                    "status" to (if (isConnected) "connected" else "disconnected"),
                    "isLocal" to isLocalDevice,
                    "connected" to isConnected,
                    "connectionType" to connectionType,
                    "clientVersion" to clientVersion
                )
                
                devices.add(deviceMap)
                Log.d(TAG, "  设备 $deviceName 更新: 连接状态=$isConnected, 类型=$connectionType, 地址=$addresses")
            }
            
            Log.d(TAG, "=== getDevicesFromSyncthing 结束 ===")
            return devices
            
        } catch (e: Exception) {
            Log.e(TAG, "获取设备列表失败", e)
            Log.d(TAG, "=== getDevicesFromSyncthing 结束（出错）===")
            // 抛出异常，让上层处理
            throw e
        }
    }
    
    /**
     * 获取设备连接信息
     * 使用与 Go 后端相同的接口: /rest/system/connections
     */
    private fun getDeviceConnectionInfo(deviceId: String): Map<String, Any> {
        return try {
            Log.d(TAG, "正在获取设备 $deviceId 的连接信息")
            val response = executeGetRequest("/rest/system/connections")
            val jsonObject = JsonParser.parseString(response).asJsonObject
            
            val connections = jsonObject.get("connections")?.asJsonObject
            if (connections != null && connections.has(deviceId)) {
                val connection = connections.get(deviceId).asJsonObject
                val connectionInfo = mapOf(
                    "connected" to (connection.get("connected")?.asBoolean ?: false),
                    "type" to (connection.get("type")?.asString ?: "unknown"),
                    "clientVersion" to (connection.get("clientVersion")?.asString ?: ""),
                    "address" to (connection.get("address")?.asString ?: ""),
                    "isLocalNetwork" to (connection.get("isLocalNetwork")?.asBoolean ?: false),
                    "crypto" to (connection.get("crypto")?.asString ?: "")
                )
                Log.d(TAG, "设备 $deviceId 连接信息: $connectionInfo")
                return connectionInfo
            }
            
            Log.d(TAG, "设备 $deviceId 未找到连接信息")
            return mapOf(
                "connected" to false,
                "type" to "unknown",
                "clientVersion" to "",
                "address" to "",
                "isLocalNetwork" to false,
                "crypto" to ""
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "获取设备 $deviceId 连接信息失败", e)
            return mapOf(
                "connected" to false,
                "type" to "unknown",
                "clientVersion" to "",
                "address" to "",
                "isLocalNetwork" to false,
                "crypto" to ""
            )
        }
    }
    
    /**
     * 获取设备地址列表
     */
    private fun getDeviceAddresses(deviceId: String, isLocalDevice: Boolean): List<String> {
        val addresses = mutableListOf<String>()
        
        try {
            // 获取设备发现信息
            Log.d(TAG, "正在获取设备 $deviceId 的发现信息")
            val response = executeGetRequest("/rest/system/discovery")
            val jsonObject = JsonParser.parseString(response).asJsonObject
            
            if (jsonObject.has(deviceId)) {
                val deviceInfo = jsonObject.get(deviceId).asJsonObject
                if (deviceInfo.has("addresses")) {
                    val addressArray = deviceInfo.get("addresses").asJsonArray
                    for (i in 0 until addressArray.size()) {
                        val address = addressArray[i].asString
                        if (!address.contains("relay://")) {
                            addresses.add(address)
                        }
                    }
                }
            }
            
            // 为本机设备添加本地地址
            if (isLocalDevice) {
                val localAddresses = getLocalNetworkAddresses()
                addresses.addAll(localAddresses)
                Log.d(TAG, "为本机设备添加本地地址: $localAddresses")
            }
            
            // 去重
            val uniqueAddresses = addresses.distinct()
            Log.d(TAG, "设备 $deviceId 地址列表: $uniqueAddresses")
            return uniqueAddresses
            
        } catch (e: Exception) {
            Log.e(TAG, "获取设备 $deviceId 地址信息失败", e)
            // 返回默认地址
            if (isLocalDevice) {
                return listOf("127.0.0.1")
            }
            return emptyList()
        }
    }
    
    /**
     * 获取本地网络地址
     */
    private fun getLocalNetworkAddresses(): List<String> {
        val addresses = mutableListOf<String>()
        
        try {
            // 获取本机网络接口地址
            val networkInterfaces = NetworkInterface.getNetworkInterfaces()
            while (networkInterfaces.hasMoreElements()) {
                val networkInterface = networkInterfaces.nextElement()
                
                // 跳过回环接口和未启用的接口
                if (networkInterface.isLoopback || !networkInterface.isUp) {
                    continue
                }
                
                val interfaceAddresses = networkInterface.inetAddresses
                while (interfaceAddresses.hasMoreElements()) {
                    val address = interfaceAddresses.nextElement()
                    
                    // 只获取 IPv4 地址
                    if (address is Inet4Address && !address.isLoopbackAddress) {
                        val hostAddress = address.hostAddress
                        if (hostAddress != null && isPrivateIPAddress(hostAddress)) {
                            addresses.add(hostAddress)
                        }
                    }
                }
            }
            
            Log.d(TAG, "本地网络地址: $addresses")
            return addresses
            
        } catch (e: Exception) {
            Log.e(TAG, "获取本地网络地址失败", e)
            return listOf("127.0.0.1")
        }
    }
    
    /**
     * 判断是否为私有 IP 地址
     */
    private fun isPrivateIPAddress(ipAddress: String): Boolean {
        return try {
            val parts = ipAddress.split(".")
            if (parts.size != 4) return false
            
            val first = parts[0].toInt()
            val second = parts[1].toInt()
            
            // 私有 IP 地址范围
            when {
                first == 10 -> true
                first == 172 && second in 16..31 -> true
                first == 192 && second == 168 -> true
                else -> false
            }
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * 处理设备文件夹请求
     */
    private fun handleDeviceFolders(uri: String): String {
        val deviceId = uri.split("/")[3] // /api/device/{deviceId}/folders
        return try {
            val folders = getFoldersFromSyncthing()
            success(folders)
        } catch (e: Exception) {
            Log.e(TAG, "获取文件夹列表失败", e)
            fail(500, "获取文件夹失败")
        }
    }
    
    /**
     * 从 Syncthing API 获取文件夹列表
     */
    private fun getFoldersFromSyncthing(): List<Map<String, Any>> {
        val response = executeGetRequest("/rest/config/folders")
        val jsonArray = JsonParser.parseString(response).asJsonArray
        
        val folders = mutableListOf<Map<String, Any>>()
        
        for (element in jsonArray) {
            val folder = element.asJsonObject
            val folderMap = mapOf(
                "id" to (folder.get("id")?.asString ?: ""),
                "label" to (folder.get("label")?.asString ?: ""),
                "path" to (folder.get("path")?.asString ?: ""),
                "type" to "sendreceive",
                "devices" to listOf<String>()
            )
            folders.add(folderMap)
        }
        
        return folders
    }
    
    /**
     * 处理文件夹文件请求
     */
    private fun handleFolderFiles(uri: String): String {
        val folderId = uri.split("/")[3] // /api/folder/{folderId}/files
        return try {
            val files = getFilesFromSyncthing(folderId)
            success(files)
        } catch (e: Exception) {
            Log.e(TAG, "获取文件列表失败", e)
            fail(500, "获取文件失败")
        }
    }
    
    /**
     * 从 Syncthing API 获取文件列表
     */
    private fun getFilesFromSyncthing(folderId: String): List<Map<String, Any>> {
        val response = executeGetRequest("/rest/db/browse?folder=$folderId")
        val jsonObject = JsonParser.parseString(response).asJsonObject
        val files = jsonObject.get("files")?.asJsonArray
        
        val fileList = mutableListOf<Map<String, Any>>()
        
        files?.forEach { element ->
            val file = element.asJsonObject
            val fileMap = mapOf(
                "name" to (file.get("name")?.asString ?: ""),
                "size" to (file.get("size")?.asLong ?: 0L),
                "modified" to (file.get("modified")?.asString ?: ""),
                "type" to (if (file.get("type")?.asString == "FILE_INFO_TYPE_DIRECTORY") "directory" else "file")
            )
            fileList.add(fileMap)
        }
        
        return fileList
    }
    
    /**
     * 处理本地设备 ID 请求
     */
    private fun handleLocalDeviceId(): String {
        return try {
            val deviceId = getLocalDeviceID()
            success(mapOf("deviceId" to deviceId))
        } catch (e: Exception) {
            Log.e(TAG, "获取本地设备 ID 失败", e)
            fail(500, "获取设备 ID 失败")
        }
    }
    
    /**
     * 获取本地设备 ID
     */
    private fun getLocalDeviceID(): String {
        val response = executeGetRequest("/rest/system/status")
        val jsonObject = JsonParser.parseString(response).asJsonObject
        return jsonObject.get("myID")?.asString ?: "unknown"
    }
    
    /**
     * 处理 WiFi 信息请求
     */
    private fun handleWifiInfo(): String {
        val wifiInfo = mapOf(
            "ssid" to "MyDataApp WiFi",
            "strength" to -50,
            "connected" to true
        )
        return success(wifiInfo)
    }
    
    /**
     * 处理文件夹共享请求
     */
    private fun handleFolderShare(uri: String): String {
        val folderId = uri.split("/")[3] // /api/folder/{folderId}/share
        return success(mapOf("message" to "文件夹共享请求已发送: $folderId"))
    }
    
    /**
     * 处理 Syncthing 事件请求
     */
    private fun handleSyncthingEvents(): String {
        val events = listOf(
            mapOf(
                "type" to "DeviceConnected",
                "time" to System.currentTimeMillis(),
                "data" to mapOf("device" to "MyDataApp")
            )
        )
        return success(events)
    }
    
    /**
     * 处理 Syncthing 设备发现请求
     */
    private fun handleSyncthingDiscovery(): String {
        Log.i(TAG, "🔍 开始处理 Syncthing 设备发现请求")
        
        // 检查 Syncthing 服务是否可用
        if (!isSyncthingServiceAvailable()) {
            Log.w(TAG, "⚠️ Syncthing 服务不可用")
            return fail(503, "Syncthing 服务不可用")
        }
        
        return try {
            Log.d(TAG, "📡 尝试从 Syncthing API 获取设备发现信息...")
            val discoveryData = getDiscoveryFromSyncthing()
            Log.i(TAG, "✅ 成功获取设备发现信息，设备数量: ${discoveryData.size}")
            Log.d(TAG, "📋 发现数据详情: $discoveryData")
            success(discoveryData)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 获取设备发现信息失败", e)
            Log.e(TAG, "🔍 异常详情: ${e.javaClass.simpleName} - ${e.message}")
            Log.e(TAG, "📚 异常堆栈: ${e.stackTraceToString()}")
            // 返回错误信息
            return fail(500, "获取设备发现信息失败: ${e.message}")
        }
    }
    
    /**
     * 执行 HTTP GET 请求到 Syncthing API
     */
    private fun executeGetRequest(endpoint: String): String {
        Log.d(TAG, "🚀 开始执行 HTTP GET 请求")
        Log.d(TAG, "🔗 请求端点: $endpoint")
        
        val client = getOrCreateHttpClient()
        val url = "$syncthingApiBase$endpoint"
        Log.d(TAG, "🌐 完整 URL: $url")
        Log.d(TAG, "🔑 API Key: $apiKey")
        
        val request = Request.Builder()
            .url(url)
            .addHeader("X-API-Key", apiKey)
            .build()
        
        Log.d(TAG, "📤 发送请求...")
        
        try {
            client.newCall(request).execute().use { response ->
                Log.d(TAG, "📥 收到响应，状态码: ${response.code}")
                Log.d(TAG, "📋 响应头: ${response.headers}")
                
                if (!response.isSuccessful) {
                    val errorBody = response.body?.string() ?: "无错误详情"
                    Log.e(TAG, "❌ HTTP 请求失败: ${response.code}")
                    Log.d(TAG, "📄 错误响应体: $errorBody")
                    throw IOException("HTTP 请求失败: ${response.code} - $errorBody")
                }
                
                val responseBody = response.body?.string()
                Log.d(TAG, "✅ 请求成功，响应体长度: ${responseBody?.length ?: 0}")
                Log.d(TAG, "📄 响应内容: $responseBody")
                return responseBody ?: ""
            }
        } catch (e: Exception) {
            Log.e(TAG, "💥 HTTP 请求执行失败", e)
            Log.e(TAG, "🔍 具体错误: ${e.javaClass.simpleName} - ${e.message}")
            throw e
        }
    }

    /**
     * 执行 HTTP POST 请求到 Syncthing API
     */
    private fun executePostRequest(endpoint: String, jsonBody: String): String {
        Log.d(TAG, "🚀 开始执行 HTTP POST 请求")
        Log.d(TAG, "🔗 请求端点: $endpoint")
        Log.d(TAG, "📄 请求体: $jsonBody")
        
        val client = getOrCreateHttpClient()
        val url = "$syncthingApiBase$endpoint"
        Log.d(TAG, "🌐 完整 URL: $url")
        Log.d(TAG, "🔑 API Key: $apiKey")
        
        val requestBody = RequestBody.create(
            "application/json; charset=utf-8".toMediaType(),
            jsonBody
        )
        
        val request = Request.Builder()
            .url(url)
            .addHeader("X-API-Key", apiKey)
            .post(requestBody)
            .build()
        
        Log.d(TAG, "📤 发送请求...")
        
        try {
            client.newCall(request).execute().use { response ->
                Log.d(TAG, "📥 收到响应，状态码: ${response.code}")
                Log.d(TAG, "📋 响应头: ${response.headers}")
                
                if (!response.isSuccessful) {
                    val errorBody = response.body?.string() ?: "无错误详情"
                    Log.e(TAG, "❌ HTTP 请求失败: ${response.code}")
                    Log.d(TAG, "📄 错误响应体: $errorBody")
                    throw IOException("HTTP 请求失败: ${response.code} - $errorBody")
                }
                
                val responseBody = response.body?.string()
                Log.d(TAG, "✅ 请求成功，响应体长度: ${responseBody?.length ?: 0}")
                Log.d(TAG, "📄 响应内容: $responseBody")
                return responseBody ?: ""
            }
        } catch (e: Exception) {
            Log.e(TAG, "💥 HTTP 请求执行失败", e)
            Log.e(TAG, "🔍 具体错误: ${e.javaClass.simpleName} - ${e.message}")
            throw e
        }
    }
    
    /**
     * 获取或创建 HTTP 客户端
     */
    private fun getOrCreateHttpClient(): OkHttpClient {
        if (httpClient != null) {
            return httpClient!!
        }
        
        // 创建信任所有证书的客户端（仅用于开发）
        val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        
        val sslContext = SSLContext.getInstance("SSL")
        sslContext.init(null, trustAllCerts, SecureRandom())
        
        val sslSocketFactory = sslContext.socketFactory
        
        httpClient = OkHttpClient.Builder()
            .sslSocketFactory(sslSocketFactory, trustAllCerts[0] as X509TrustManager)
            .hostnameVerifier { _, _ -> true }
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
        
        return httpClient!!
    }
    
    /**
     * 从 Syncthing API 获取设备发现信息
     */
    private fun getDiscoveryFromSyncthing(): Map<String, Any> {
        Log.d(TAG, "🌐 开始调用 Syncthing API: /rest/system/discovery")
        
        try {
            val response = executeGetRequest("/rest/system/discovery")
            Log.d(TAG, "📥 收到 Syncthing API 响应，长度: ${response.length}")
            Log.d(TAG, "📄 响应内容: $response")
            
            val jsonObject = JsonParser.parseString(response).asJsonObject
            Log.d(TAG, "🔍 JSON 解析成功，根对象键数量: ${jsonObject.size()}")
            
            val discoveryData = mutableMapOf<String, Any>()
            
            // 遍历所有发现的设备
            for (entry in jsonObject.entrySet()) {
                val deviceId = entry.key
                val deviceData = entry.value.asJsonObject
                Log.d(TAG, "📱 处理设备: $deviceId")
                
                val addresses = mutableListOf<String>()
                if (deviceData.has("addresses")) {
                    val addressesArray = deviceData.get("addresses").asJsonArray
                    Log.d(TAG, "📍 设备 $deviceId 有 ${addressesArray.size()} 个地址")
                    
                    for (addrElement in addressesArray) {
                        val address = addrElement.asString
                        addresses.add(address)
                        Log.d(TAG, "🌍 添加地址: $address")
                    }
                } else {
                    Log.w(TAG, "⚠️ 设备 $deviceId 没有地址信息")
                }
                
                discoveryData[deviceId] = mapOf("addresses" to addresses)
                Log.d(TAG, "✅ 设备 $deviceId 处理完成，地址数量: ${addresses.size}")
            }
            
            Log.i(TAG, "🎉 设备发现信息获取完成，总共 ${discoveryData.size} 个设备")
            return discoveryData
            
        } catch (e: Exception) {
            Log.e(TAG, "💥 getDiscoveryFromSyncthing 方法执行失败", e)
            Log.e(TAG, "🔍 具体错误: ${e.javaClass.simpleName} - ${e.message}")
            throw e
        }
    }
    
    /**
     * 检查 Syncthing 服务是否可用
     */
    private fun isSyncthingServiceAvailable(): Boolean {
        Log.d(TAG, "🔍 检查 Syncthing 服务是否可用...")
        
        try {
            // 尝试连接 Syncthing API 的状态端点
            val client = getOrCreateHttpClient()
            val url = "$syncthingApiBase/rest/system/status"
            
            val request = Request.Builder()
                .url(url)
                .addHeader("X-API-Key", apiKey)
                .build()
            
            Log.d(TAG, "🌐 测试连接: $url")
            
            client.newCall(request).execute().use { response ->
                val isAvailable = response.isSuccessful
                Log.d(TAG, "📡 Syncthing 服务状态: ${if (isAvailable) "可用" else "不可用"} (状态码: ${response.code})")
                return isAvailable
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Syncthing 服务不可用: ${e.message}")
            return false
        }
    }
    
    /**
     * 从 Syncthing 配置文件获取 API Key
     * 如果获取失败，将抛出异常
     */
    private fun getApiKeyFromConfig(): String {
        Log.d(TAG, "🔍 尝试从 Syncthing 配置文件获取 API Key")
        
        // 主要配置文件路径
        val configPath = "/data/data/tech.shupi.mydata/files/config.xml"
        
        try {
            val file = File(configPath)
            if (file.exists()) {
                Log.d(TAG, "📁 找到配置文件: $configPath")
                val content = file.readText()
                
                // 简单的 XML 解析，查找 apikey 标签
                val apiKeyPattern = Regex("<apikey>([^<]+)</apikey>")
                val matchResult = apiKeyPattern.find(content)
                
                if (matchResult != null) {
                    val apiKey = matchResult.groupValues[1]
                    if (apiKey.isNotEmpty()) {
                        Log.d(TAG, "✅ 成功从配置文件获取 API Key: ${apiKey.take(8)}...")
                        return apiKey
                    } else {
                        Log.w(TAG, "⚠️ 配置文件中的 API Key 为空")
                    }
                } else {
                    Log.w(TAG, "⚠️ 配置文件中未找到 apikey 标签")
                }
            } else {
                Log.e(TAG, "❌ 配置文件不存在: $configPath")
            }
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ 读取配置文件失败: $configPath", e)
        }
        
        // 如果获取失败，抛出异常
        val errorMessage = "无法从配置文件获取有效的 API Key: $configPath"
        Log.e(TAG, "💥 $errorMessage")
        throw IllegalStateException(errorMessage)
    }
    
    /**
     * 发送成功响应
     */
    private fun success(data: Any): String {
        val response = mapOf(
            "success" to true,
            "data" to data
        )
        return gson.toJson(response)
    }
    
    /**
     * 发送失败响应
     */
    private fun fail(code: Int, message: String): String {
        val response = mapOf(
            "success" to false,
            "error" to mapOf(
                "code" to code,
                "message" to message
            )
        )
        return gson.toJson(response)
    }
    
    /**
     * 发送错误响应
     */
    private fun sendErrorResponse(output: OutputStream, statusCode: Int, message: String) {
        val errorResponse = fail(statusCode, message)
        val responseBytes = errorResponse.toByteArray(Charsets.UTF_8)
        val httpResponse = """
            HTTP/1.1 $statusCode $message
            Content-Type: application/json; charset=utf-8
            Content-Length: ${responseBytes.size}
            Connection: close
            
        """.trimIndent() + "\r\n"
        
        output.write(httpResponse.toByteArray(Charsets.UTF_8))
        output.write(responseBytes)
        output.flush()
    }
}

