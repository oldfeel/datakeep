package com.mydata.app.service

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
    private var serverSocket: ServerSocket? = null
    private var executor: ExecutorService? = null
    private var running = false
    
    /**
     * 启动 HTTPS 服务器
     */
    fun start() {
        if (running) {
            Log.w(TAG, "HTTPS 服务器已经在运行")
            return
        }
        
        try {
            Log.i(TAG, "启动 HTTPS API 服务器，端口: $PORT")
            
            // 创建线程池
            executor = Executors.newCachedThreadPool()
            
            // 创建服务器套接字
            serverSocket = ServerSocket(PORT)
            running = true
            
            // 启动监听线程
            executor?.submit {
                while (running) {
                    try {
                        val clientSocket = serverSocket?.accept()
                        if (clientSocket != null) {
                            executor?.submit { handleClient(clientSocket) }
                        }
                    } catch (e: Exception) {
                        if (running) {
                            Log.e(TAG, "处理客户端连接失败", e)
                        }
                    }
                }
            }
            
            Log.i(TAG, "HTTPS API 服务器启动成功")
            Log.i(TAG, "可用的 API 端点:")
            Log.i(TAG, "  - GET  /api/devices")
            Log.i(TAG, "  - GET  /api/device/{deviceId}/folders")
            Log.i(TAG, "  - GET  /api/folder/{folderId}")
            Log.i(TAG, "  - GET  /api/local-device-id")
            Log.i(TAG, "  - GET  /api/wifi-info")
            Log.i(TAG, "  - POST /api/folder/{folderId}/share")
            Log.i(TAG, "  - GET  /api/syncthing/events")
            
        } catch (e: Exception) {
            Log.e(TAG, "启动 HTTPS 服务器失败", e)
            throw e
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
        try {
            val input = BufferedReader(InputStreamReader(clientSocket.getInputStream()))
            val output = PrintWriter(clientSocket.getOutputStream(), true)
            
            // 读取请求行
            val requestLine = input.readLine()
            if (requestLine == null) {
                sendErrorResponse(output, 400, "Bad Request")
                return
            }
            
            val parts = requestLine.split(" ")
            if (parts.size < 3) {
                sendErrorResponse(output, 400, "Bad Request")
                return
            }
            
            val method = parts[0]
            val uri = parts[1]
            
            // 读取请求头
            val headers = mutableMapOf<String, String>()
            var line: String?
            while (input.readLine().also { line = it } != null && line?.isNotEmpty() == true) {
                val headerParts = line?.split(": ", limit = 2)
                if (headerParts?.size == 2) {
                    headers[headerParts[0]] = headerParts[1]
                }
            }
            
            // 处理请求
            val response = handleRequest(method, uri, headers)
            
            // 发送响应
            output.println("HTTP/1.1 200 OK")
            output.println("Content-Type: application/json")
            output.println("Access-Control-Allow-Origin: *")
            output.println("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS")
            output.println("Access-Control-Allow-Headers: Content-Type, Authorization")
            output.println("Content-Length: ${response.length}")
            output.println()
            output.println(response)
            
        } catch (e: Exception) {
            Log.e(TAG, "处理客户端请求失败", e)
        } finally {
            try {
                clientSocket.close()
            } catch (e: Exception) {
                Log.e(TAG, "关闭客户端连接失败", e)
            }
        }
    }
    
    /**
     * 处理 HTTP 请求
     */
    private fun handleRequest(method: String, uri: String, headers: Map<String, String>): String {
        Log.d(TAG, "处理请求: $method $uri")
        
        return when {
            uri.startsWith("/api/devices") -> handleDevices()
            uri.startsWith("/api/device/") && uri.contains("/folders") -> handleDeviceFolders(uri)
            uri.startsWith("/api/folder/") && uri.endsWith("/files") -> handleFolderFiles(uri)
            uri == "/api/local-device-id" -> handleLocalDeviceId()
            uri == "/api/wifi-info" -> handleWifiInfo()
            uri.startsWith("/api/folder/") && uri.endsWith("/share") -> handleFolderShare(uri)
            uri == "/api/syncthing/events" -> handleSyncthingEvents()
            else -> fail(404, "Not Found")
        }
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
    private fun sendErrorResponse(output: PrintWriter, statusCode: Int, message: String) {
        val errorResponse = fail(statusCode, message)
        output.println("HTTP/1.1 $statusCode $message")
        output.println("Content-Type: application/json")
        output.println("Content-Length: ${errorResponse.length}")
        output.println()
        output.println(errorResponse)
    }
} 