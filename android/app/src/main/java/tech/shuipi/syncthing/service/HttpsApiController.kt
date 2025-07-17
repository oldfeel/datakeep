package tech.shuipi.syncthing.service

import android.content.Context
import android.util.Log
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.http.*
import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.client.call.body
import io.ktor.http.content.*
import kotlinx.coroutines.runBlocking
import java.io.IOException

/**
 * HTTPS API 代理控制器
 * 在本地启动 HTTP 服务器，代理所有请求到 Syncthing REST API
 */
class HttpsApiController(private val context: Context) {
    companion object {
        private const val TAG = "HttpsApiController"
        private const val PORT = 3434
        private const val SYNCTHING_URL = "http://127.0.0.1:8384"
    }
    
    private var server: EmbeddedServer<NettyApplicationEngine, NettyApplicationEngine.Configuration>? = null
    private val httpClient = HttpClient()
    
    /**
     * 启动 HTTP 服务器
     */
    fun start() {
        if (server != null) {
            Log.w(TAG, "Server already running")
            return
        }
        
        try {
            server = embeddedServer(Netty, host = "0.0.0.0", port = PORT) {
                routing {
                    // 代理所有请求到 syncthing
                    route("/{...}") {
                        handle {
                            call.proxyToSyncthing()
                        }
                    }
                    
                    // 健康检查端点
                    get("/health") {
                        call.respondText("OK", ContentType.Text.Plain)
                    }
                }
            }
            
            server?.start(wait = false)
            Log.i(TAG, "HTTPS API Controller started on port $PORT, host 0.0.0.0 (LAN accessible)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start HTTPS API Controller", e)
        }
    }
    
    /**
     * 停止 HTTP 服务器
     */
    fun stop() {
        try {
            server?.stop(1000, 2000)
            server = null
            httpClient.close()
            Log.i(TAG, "HTTPS API Controller stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop HTTPS API Controller", e)
        }
    }
    
    /**
     * 代理请求到 Syncthing
     */
    private suspend fun ApplicationCall.proxyToSyncthing() {
        try {
            val path = request.uri
            val method = request.httpMethod
            val headers = request.headers
            val queryString = request.queryString()
            
            Log.d(TAG, "Proxying request: $method $path")
            
            // 构建目标 URL
            val targetUrl = if (queryString.isNotEmpty()) {
                "$SYNCTHING_URL$path?$queryString"
            } else {
                "$SYNCTHING_URL$path"
            }
            
            // 读取请求体
            val body = when (method) {
                HttpMethod.Post, HttpMethod.Put, HttpMethod.Patch -> {
                    try {
                        receiveText()
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to read request body", e)
                        null
                    }
                }
                else -> null
            }
            
            // 转发请求到 syncthing
            val syncthingResponse = httpClient.request(targetUrl) {
                this.method = method
                
                // 转发请求头（排除一些不需要的）
                headers.forEach { key, values ->
                    if (!key.equals("Host", ignoreCase = true) && 
                        !key.equals("Content-Length", ignoreCase = true)) {
                        values.forEach { value ->
                            this.headers.append(key, value)
                        }
                    }
                }
                
                // 设置请求体
                body?.let { 
                    setBody(it)
                    this.headers.append("Content-Type", "application/json")
                }
            }
            
            // 获取响应内容
            val responseBody = try {
                syncthingResponse.bodyAsText()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to read response body", e)
                ""
            }
            
            // 返回 syncthing 的响应
            respondText(responseBody, status = syncthingResponse.status)
            
            Log.d(TAG, "Proxied response: ${syncthingResponse.status}")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to proxy request", e)
            respondText(
                """{"error": "Failed to proxy request: ${e.message}"}""", 
                ContentType.Application.Json,
                HttpStatusCode.InternalServerError
            )
        }
    }
    
    /**
     * 检查服务器是否正在运行
     */
    fun isRunning(): Boolean {
        return server != null
    }
    
    /**
     * 获取服务器端口
     */
    fun getPort(): Int = PORT
    
    /**
     * 获取服务器 URL
     */
    fun getServerUrl(): String = "http://127.0.0.1:$PORT"
} 