package tech.shuipi.syncthing.utils

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Syncthing API 封装类
 * 提供常用的 Syncthing REST API 调用方法
 */
class SyncthingApi {
    companion object {
        private const val TAG = "SyncthingApi"
    }
    
    private val apiClient = ApiClient()
    
    /**
     * 获取系统状态
     */
    suspend fun getSystemStatus(): ApiResponse = withContext(Dispatchers.IO) {
        try {
            apiClient.get("/rest/system/status")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get system status", e)
            ApiResponse(false, -1, null, e.message)
        }
    }
    
    /**
     * 获取系统版本
     */
    suspend fun getSystemVersion(): ApiResponse = withContext(Dispatchers.IO) {
        try {
            apiClient.get("/rest/system/version")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get system version", e)
            ApiResponse(false, -1, null, e.message)
        }
    }
    
    /**
     * 获取设备列表
     */
    suspend fun getDevices(): ApiResponse = withContext(Dispatchers.IO) {
        try {
            apiClient.get("/rest/config/devices")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get devices", e)
            ApiResponse(false, -1, null, e.message)
        }
    }
    
    /**
     * 获取文件夹列表
     */
    suspend fun getFolders(): ApiResponse = withContext(Dispatchers.IO) {
        try {
            apiClient.get("/rest/config/folders")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get folders", e)
            ApiResponse(false, -1, null, e.message)
        }
    }
    
    /**
     * 获取连接状态
     */
    suspend fun getConnections(): ApiResponse = withContext(Dispatchers.IO) {
        try {
            apiClient.get("/rest/system/connections")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get connections", e)
            ApiResponse(false, -1, null, e.message)
        }
    }
    
    /**
     * 重启 Syncthing
     */
    suspend fun restart(): ApiResponse = withContext(Dispatchers.IO) {
        try {
            apiClient.post("/rest/system/restart")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restart syncthing", e)
            ApiResponse(false, -1, null, e.message)
        }
    }
    
    /**
     * 关闭 Syncthing
     */
    suspend fun shutdown(): ApiResponse = withContext(Dispatchers.IO) {
        try {
            apiClient.post("/rest/system/shutdown")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to shutdown syncthing", e)
            ApiResponse(false, -1, null, e.message)
        }
    }
    
    /**
     * 检查 API 服务器健康状态
     */
    suspend fun checkHealth(): Boolean = withContext(Dispatchers.IO) {
        try {
            apiClient.checkHealth()
        } catch (e: Exception) {
            Log.e(TAG, "Health check failed", e)
            false
        }
    }
    
    /**
     * 获取设备 ID
     */
    suspend fun getDeviceId(): String? = withContext(Dispatchers.IO) {
        try {
            val response = getSystemStatus()
            if (response.success && response.data != null) {
                val json = JSONObject(response.data)
                json.optString("myID", null)
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get device ID", e)
            null
        }
    }
    
    /**
     * 关闭 API 客户端
     */
    fun close() {
        apiClient.close()
    }
} 