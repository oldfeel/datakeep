package tech.shuipi.syncthing.utils

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * API 客户端工具类
 * 用于前端与本地 HTTPS API Controller 通信
 */
class ApiClient {
    companion object {
        private const val TAG = "ApiClient"
        private const val BASE_URL = "http://127.0.0.1:3434"
        private const val TIMEOUT_SECONDS = 10L
    }
    
    private val client = OkHttpClient.Builder()
        .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .writeTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()
    
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    
    /**
     * GET 请求
     */
    suspend fun get(endpoint: String): ApiResponse = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url("$BASE_URL$endpoint")
                .get()
                .build()
            
            Log.d(TAG, "GET request: $BASE_URL$endpoint")
            
            client.newCall(request).execute().use { response ->
                val body = response.body?.string() ?: ""
                Log.d(TAG, "GET response: ${response.code} - $body")
                
                ApiResponse(
                    success = response.isSuccessful,
                    code = response.code,
                    data = body,
                    error = if (!response.isSuccessful) body else null
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "GET request failed", e)
            ApiResponse(
                success = false,
                code = -1,
                data = null,
                error = e.message ?: "Unknown error"
            )
        }
    }
    
    /**
     * POST 请求
     */
    suspend fun post(endpoint: String, data: String? = null): ApiResponse = withContext(Dispatchers.IO) {
        try {
            val requestBuilder = Request.Builder()
                .url("$BASE_URL$endpoint")
            
            if (data != null) {
                val body = data.toRequestBody(jsonMediaType)
                requestBuilder.post(body)
            } else {
                requestBuilder.post("".toRequestBody())
            }
            
            val request = requestBuilder.build()
            Log.d(TAG, "POST request: $BASE_URL$endpoint - $data")
            
            client.newCall(request).execute().use { response ->
                val body = response.body?.string() ?: ""
                Log.d(TAG, "POST response: ${response.code} - $body")
                
                ApiResponse(
                    success = response.isSuccessful,
                    code = response.code,
                    data = body,
                    error = if (!response.isSuccessful) body else null
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "POST request failed", e)
            ApiResponse(
                success = false,
                code = -1,
                data = null,
                error = e.message ?: "Unknown error"
            )
        }
    }
    
    /**
     * PUT 请求
     */
    suspend fun put(endpoint: String, data: String? = null): ApiResponse = withContext(Dispatchers.IO) {
        try {
            val requestBuilder = Request.Builder()
                .url("$BASE_URL$endpoint")
            
            if (data != null) {
                val body = data.toRequestBody(jsonMediaType)
                requestBuilder.put(body)
            } else {
                requestBuilder.put("".toRequestBody())
            }
            
            val request = requestBuilder.build()
            Log.d(TAG, "PUT request: $BASE_URL$endpoint - $data")
            
            client.newCall(request).execute().use { response ->
                val body = response.body?.string() ?: ""
                Log.d(TAG, "PUT response: ${response.code} - $body")
                
                ApiResponse(
                    success = response.isSuccessful,
                    code = response.code,
                    data = body,
                    error = if (!response.isSuccessful) body else null
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "PUT request failed", e)
            ApiResponse(
                success = false,
                code = -1,
                data = null,
                error = e.message ?: "Unknown error"
            )
        }
    }
    
    /**
     * DELETE 请求
     */
    suspend fun delete(endpoint: String): ApiResponse = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url("$BASE_URL$endpoint")
                .delete()
                .build()
            
            Log.d(TAG, "DELETE request: $BASE_URL$endpoint")
            
            client.newCall(request).execute().use { response ->
                val body = response.body?.string() ?: ""
                Log.d(TAG, "DELETE response: ${response.code} - $body")
                
                ApiResponse(
                    success = response.isSuccessful,
                    code = response.code,
                    data = body,
                    error = if (!response.isSuccessful) body else null
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "DELETE request failed", e)
            ApiResponse(
                success = false,
                code = -1,
                data = null,
                error = e.message ?: "Unknown error"
            )
        }
    }
    
    /**
     * 检查 API 服务器是否可用
     */
    suspend fun checkHealth(): Boolean = withContext(Dispatchers.IO) {
        try {
            val response = get("/health")
            response.success
        } catch (e: Exception) {
            Log.e(TAG, "Health check failed", e)
            false
        }
    }
    
    /**
     * 关闭客户端
     */
    fun close() {
        client.dispatcher.executorService.shutdown()
        client.connectionPool.evictAll()
    }
}

/**
 * API 响应数据类
 */
data class ApiResponse(
    val success: Boolean,
    val code: Int,
    val data: String?,
    val error: String?
) 