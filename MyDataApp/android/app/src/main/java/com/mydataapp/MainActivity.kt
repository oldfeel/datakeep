package com.mydataapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate
import com.mydata.app.service.SyncthingService

class MainActivity : ReactActivity() {
    
    companion object {
        private const val TAG = "MainActivity"
        private const val PERMISSION_REQUEST_CODE = 1001
    }
    
    // 需要请求的权限列表
    private val requiredPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        arrayOf(
            Manifest.permission.POST_NOTIFICATIONS,
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE
        )
    } else {
        arrayOf(
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE
        )
    }
    
    // 权限请求回调
    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.entries.all { it.value }
        if (allGranted) {
            Log.i(TAG, "所有权限已授予，启动 Syncthing 服务")
            startSyncthingService()
        } else {
            Log.w(TAG, "部分权限被拒绝")
            // 可以在这里显示权限说明对话框
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate")
        
        // 检查并请求权限
        checkAndRequestPermissions()
    }

    /**
     * 检查并请求必要权限
     */
    private fun checkAndRequestPermissions() {
        val permissionsToRequest = mutableListOf<String>()
        
        for (permission in requiredPermissions) {
            if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(permission)
            }
        }
        
        if (permissionsToRequest.isEmpty()) {
            Log.i(TAG, "所有权限已授予")
            startSyncthingService()
        } else {
            Log.i(TAG, "请求权限: ${permissionsToRequest.joinToString()}")
            permissionLauncher.launch(permissionsToRequest.toTypedArray())
        }
    }
    
    /**
     * 启动 Syncthing 服务
     */
    private fun startSyncthingService() {
        try {
            Log.i(TAG, "启动 Syncthing 服务")
            val intent = Intent(this, SyncthingService::class.java).apply {
                action = SyncthingService.ACTION_START
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            
            Log.i(TAG, "Syncthing 服务启动成功")
            
        } catch (e: Exception) {
            Log.e(TAG, "启动 Syncthing 服务失败", e)
        }
    }

    /**
     * Returns the name of the main component registered from JavaScript. This is used to schedule
     * rendering of the component.
     */
    override fun getMainComponentName(): String = "MyDataApp"

    /**
     * Returns the instance of the [ReactActivityDelegate]. We use [DefaultReactActivityDelegate]
     * which allows you to enable New Architecture with a single boolean flags [fabricEnabled]
     */
    override fun createReactActivityDelegate(): ReactActivityDelegate =
        DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled)
}
