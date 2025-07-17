package tech.shuipi.syncthing

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import tech.shuipi.syncthing.service.SyncthingService
import tech.shuipi.syncthing.ui.theme.MyApplicationTheme
import tech.shuipi.syncthing.utils.ApiClient
import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    
    companion object {
        private const val TAG = "MainActivity"
        private const val REQUEST_CODE_STORAGE = 100
    }
    
    private var syncthingService: SyncthingService? = null
    private var bound = false
    
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            // 使用安全的类型转换，避免 ClassCastException
            val binder = service as? tech.shuipi.syncthing.service.SyncthingServiceBinder
            if (binder != null) {
                syncthingService = binder.getService()
                bound = true
                Log.d(TAG, "SyncthingService connected")
            } else {
                Log.e(TAG, "Failed to cast service to SyncthingServiceBinder")
                bound = false
            }
        }
    
        override fun onServiceDisconnected(arg0: ComponentName) {
            bound = false
            Log.d(TAG, "SyncthingService disconnected")
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        
        // 应用启动时自动检查权限并启动服务
        checkAndRequestPermissions()
        
        setContent {
            MyApplicationTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    SyncthingStatusScreen(
                        modifier = Modifier.padding(innerPadding),
                        onStartClick = {
                            // 重新启动服务
                            startSyncthingService()
                        }
                    )
                }
            }
        }
    }
    
    override fun onStart() {
        super.onStart()
        // 绑定到 Syncthing 服务
        Intent(this, SyncthingService::class.java).also { intent ->
            bindService(intent, connection, Context.BIND_AUTO_CREATE)
        }
    }
    
    override fun onStop() {
        super.onStop()
        // 解绑服务
        if (bound) {
            unbindService(connection)
            bound = false
        }
    }
    
    private fun startSyncthingService() {
        val intent = Intent(this, SyncthingService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        Log.d(TAG, "SyncthingService started")
    }

    private fun checkAndRequestPermissions() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQUEST_CODE_STORAGE
            )
        } else {
            // 有权限，直接启动服务
            startSyncthingService()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_STORAGE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startSyncthingService()
            } else {
                Toast.makeText(this, "需要存储权限才能运行", Toast.LENGTH_SHORT).show()
            }
        }
    }
}

@Composable
fun SyncthingStatusScreen(
    modifier: Modifier = Modifier,
    onStartClick: () -> Unit = {}
) {
    var serviceState by remember { mutableStateOf(SyncthingService.State.DISABLED) }
    var deviceId by remember { mutableStateOf("") }
    
    Column(
        modifier = modifier.padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "MyData Android",
            style = MaterialTheme.typography.headlineMedium
        )
        
        Card(
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "Syncthing 状态",
                    style = MaterialTheme.typography.titleMedium
                )
                
                Text(
                    text = when (serviceState) {
                        SyncthingService.State.INIT -> "初始化中"
                        SyncthingService.State.STARTING -> "启动中"
                        SyncthingService.State.ACTIVE -> "运行中"
                        SyncthingService.State.DISABLED -> "已停止"
                        SyncthingService.State.ERROR -> "错误"
                    },
                    color = when (serviceState) {
                        SyncthingService.State.ACTIVE -> MaterialTheme.colorScheme.primary
                        SyncthingService.State.ERROR -> MaterialTheme.colorScheme.error
                        else -> MaterialTheme.colorScheme.onSurface
                    }
                )
                
                if (deviceId.isNotEmpty()) {
                    Text(
                        text = "设备 ID: $deviceId",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }
        
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Button(
                onClick = { onStartClick() }
            ) {
                Text("重启")
            }
            
            Button(
                onClick = {
                    // 停止 Syncthing
                }
            ) {
                Text("停止")
            }
            
            Button(
                onClick = {
                    // 重启 Syncthing
                }
            ) {
                Text("重启")
            }
        }
    }
}