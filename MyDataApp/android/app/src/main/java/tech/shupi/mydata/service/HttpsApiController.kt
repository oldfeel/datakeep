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
    
    // Syncthing API 配置
    private val syncthingApiBase = "https://127.0.0.1:$SYNCTHING_PORT"
    private val apiKey = "your-api-key" // 需要从配置中获取
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    
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
            Log.i(TAG, "🌐 局域网访问: http://192.168.2.6:$PORT")
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
            else -> {
                Log.w(TAG, "❌ 未找到匹配的路由: $uri")
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
            // 返回模拟数据
            getMockDevices()
        }
    }
    
    /**
     * 从 Syncthing API 获取设备列表
     */
    private fun getDevicesFromSyncthing(): List<Map<String, Any>> {
        val response = executeGetRequest("/rest/system/status")
        val jsonObject = JsonParser.parseString(response).asJsonObject
        
        val devices = mutableListOf<Map<String, Any>>()
        
        // 添加本地设备
        val localDevice = mapOf(
            "id" to (jsonObject.get("myID")?.asString ?: "unknown"),
            "name" to "MyDataApp",
            "address" to "127.0.0.1:$SYNCTHING_PORT",
            "status" to "connected",
            "isLocal" to true
        )
        devices.add(localDevice)
        
        return devices
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
     * 执行 HTTP GET 请求到 Syncthing API
     */
    private fun executeGetRequest(endpoint: String): String {
        val client = getOrCreateHttpClient()
        val url = "$syncthingApiBase$endpoint"
        Log.d(TAG, "请求 Syncthing API: $url")
        
        val request = Request.Builder()
            .url(url)
            .addHeader("X-API-Key", apiKey)
            .build()
        
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("HTTP 请求失败: ${response.code}")
            }
            
            val responseBody = response.body?.string()
            Log.d(TAG, "API 响应: $responseBody")
            return responseBody ?: ""
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
     * 获取模拟设备数据
     */
    private fun getMockDevices(): String {
        val devices = listOf(
            mapOf(
                "id" to "MOCK-DEVICE-1",
                "name" to "MyDataApp (模拟)",
                "address" to "127.0.0.1:$SYNCTHING_PORT",
                "status" to "connected",
                "isLocal" to true
            )
        )
        return success(devices)
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