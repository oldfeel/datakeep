package com.nutomic.syncthingandroid.service;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.BufferedReader;

/**
 * 管理 MyData API 进程的服务
 * 参考 SyncthingRunnable 的实现方式
 */
public class MyDataApiService extends Service {
    private static final String TAG = "MyDataApiService";
    private static final String BINARY_NAME = "libmydata-api.so";
    private static final String CHANNEL_ID = "mydata_api_service";
    private static final int NOTIFICATION_ID = 1001;
    
    private Process mApiProcess;
    private Thread mLogThread;
    private boolean mIsRunning = false;

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "MyDataApiService created");
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "MyDataApiService started");
        
        if (!mIsRunning) {
            startApiProcess();
        }
        
        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification());
        
        return START_STICKY; // 服务被杀死后自动重启
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "MyDataApiService destroyed");
        stopApiProcess();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "MyData API Service",
                NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("MyData API 后台服务");
            
            NotificationManager notificationManager = getSystemService(NotificationManager.class);
            if (notificationManager != null) {
                notificationManager.createNotificationChannel(channel);
            }
        }
    }

    private Notification createNotification() {
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(this, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(this);
        }
        
        return builder
            .setContentTitle("MyData API")
            .setContentText("API 服务正在运行")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build();
    }

    private void startApiProcess() {
        try {
            // 读取并打印 config.xml 内容
            readAndLogConfigXml();
            
            // 获取二进制文件路径
            File binaryFile = new File(getApplicationInfo().nativeLibraryDir, BINARY_NAME);
            
            if (!binaryFile.exists()) {
                Log.e(TAG, "API binary not found: " + binaryFile.getAbsolutePath());
                return;
            }

            // 设置可执行权限
            binaryFile.setExecutable(true);
            Log.i(TAG, "Binary file: " + binaryFile.getAbsolutePath());

            // 确保必要的目录存在
            File filesDir = getFilesDir();
            File cacheDir = getCacheDir();
            
            if (!filesDir.exists()) {
                boolean created = filesDir.mkdirs();
                Log.i(TAG, "Created files directory: " + created + " at " + filesDir.getAbsolutePath());
            } else {
                Log.i(TAG, "Files directory already exists: " + filesDir.getAbsolutePath());
            }
            
            if (!cacheDir.exists()) {
                boolean created = cacheDir.mkdirs();
                Log.i(TAG, "Created cache directory: " + created + " at " + cacheDir.getAbsolutePath());
            } else {
                Log.i(TAG, "Cache directory already exists: " + cacheDir.getAbsolutePath());
            }

            // 构建命令
            String[] command = {
                binaryFile.getAbsolutePath()
            };

            // 启动进程
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.directory(filesDir);
            
            // 设置环境变量
            pb.environment().put("ANDROID_DATA", filesDir.getParent()); // 指向 /data/data/com.nutomic.syncthingandroid
            pb.environment().put("TMPDIR", cacheDir.getAbsolutePath());
            pb.environment().put("HOME", filesDir.getAbsolutePath());
            
            Log.i(TAG, "Environment variables:");
            Log.i(TAG, "  ANDROID_DATA: " + pb.environment().get("ANDROID_DATA"));
            Log.i(TAG, "  TMPDIR: " + pb.environment().get("TMPDIR"));
            Log.i(TAG, "  HOME: " + pb.environment().get("HOME"));
            
            mApiProcess = pb.start();
            mIsRunning = true;

            Log.i(TAG, "API process started with PID: " + getProcessId(mApiProcess));

            // 启动日志监控线程
            startLogMonitoring();

        } catch (IOException e) {
            Log.e(TAG, "Failed to start API process", e);
        }
    }

    /**
     * 读取并打印 config.xml 内容
     */
    private void readAndLogConfigXml() {
        // 检查多个可能的配置文件路径
        String[] possiblePaths = {
            "/data/data/com.nutomic.syncthingandroid/files/config.xml",
            "/data/data/com.nutomic.syncthingandroid.debug/files/config.xml",
            "/data/data/com.nutomic.syncthingandroid/files/syncthing/config.xml",
            "/data/data/com.nutomic.syncthingandroid.debug/files/syncthing/config.xml",
            getFilesDir().getAbsolutePath() + "/config.xml",
            getFilesDir().getAbsolutePath() + "/syncthing/config.xml"
        };
        
        boolean foundConfig = false;
        
        for (String configPath : possiblePaths) {
            File configFile = new File(configPath);
            Log.i(TAG, "检查配置文件路径: " + configPath + " (存在: " + configFile.exists() + ")");
            
            if (configFile.exists()) {
                foundConfig = true;
                try {
                    java.io.FileInputStream fis = new java.io.FileInputStream(configFile);
                    byte[] buffer = new byte[(int) configFile.length()];
                    fis.read(buffer);
                    fis.close();
                    String configContent = new String(buffer, "UTF-8");
                    
                    Log.i(TAG, "=== config.xml 内容开始 ===");
                    Log.i(TAG, "文件路径: " + configPath);
                    Log.i(TAG, "文件大小: " + configFile.length() + " 字节");
                    
                    // 查找并打印 folder 标签
                    String[] lines = configContent.split("\n");
                    boolean foundFolder = false;
                    for (String line : lines) {
                        line = line.trim();
                        if (line.contains("<folder") || line.contains("</folder>") || 
                            (line.contains("id=") && line.contains("label=") && line.contains("path="))) {
                            Log.i(TAG, "FOLDER: " + line);
                            foundFolder = true;
                        }
                    }
                    
                    if (!foundFolder) {
                        Log.w(TAG, "未找到任何 <folder> 标签");
                    }
                    
                    Log.i(TAG, "=== config.xml 内容结束 ===");
                    break; // 找到第一个存在的配置文件就停止
                    
                } catch (Exception e) {
                    Log.e(TAG, "读取 config.xml 失败: " + e.getMessage(), e);
                }
            }
        }
        
        if (!foundConfig) {
            Log.w(TAG, "所有可能的配置文件路径都不存在");
            Log.w(TAG, "请确保 Syncthing Android 应用已启动并创建了同步文件夹");
            
            // 列出当前应用的文件目录内容
            try {
                File filesDir = getFilesDir();
                Log.i(TAG, "当前应用文件目录: " + filesDir.getAbsolutePath());
                if (filesDir.exists()) {
                    File[] files = filesDir.listFiles();
                    if (files != null) {
                        Log.i(TAG, "文件目录内容:");
                        for (File file : files) {
                            Log.i(TAG, "  - " + file.getName() + " (" + (file.isDirectory() ? "目录" : "文件") + ")");
                        }
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "列出文件目录失败: " + e.getMessage());
            }
        }
    }

    private void stopApiProcess() {
        if (mApiProcess != null) {
            Log.i(TAG, "Stopping API process...");
            
            // 先尝试优雅关闭
            mApiProcess.destroy();
            
            // 等待一段时间
            try {
                Thread.sleep(3000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            
            // 如果还在运行，强制关闭
            if (mApiProcess.isAlive()) {
                Log.w(TAG, "Force killing API process");
                mApiProcess.destroyForcibly();
            }
            
            mApiProcess = null;
            mIsRunning = false;
        }

        if (mLogThread != null && mLogThread.isAlive()) {
            mLogThread.interrupt();
            mLogThread = null;
        }
    }

    private void startLogMonitoring() {
        mLogThread = new Thread(() -> {
            try {
                // 监控标准输出
                monitorStream(mApiProcess.getInputStream(), "STDOUT");
                
                // 监控标准错误
                monitorStream(mApiProcess.getErrorStream(), "STDERR");
                
                // 等待进程结束
                int exitCode = mApiProcess.waitFor();
                Log.i(TAG, "API process exited with code: " + exitCode);
                
            } catch (InterruptedException e) {
                Log.i(TAG, "Log monitoring interrupted");
            } catch (IOException e) {
                Log.e(TAG, "Error monitoring API process", e);
            } finally {
                mIsRunning = false;
            }
        });
        mLogThread.start();
    }

    private void monitorStream(InputStream stream, String type) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(stream));
        String line;
        while ((line = reader.readLine()) != null) {
            Log.d(TAG, "API " + type + ": " + line);
        }
    }

    private int getProcessId(Process process) {
        try {
            // 使用反射获取进程 ID
            java.lang.reflect.Field pidField = process.getClass().getDeclaredField("pid");
            pidField.setAccessible(true);
            return (Integer) pidField.get(process);
        } catch (Exception e) {
            Log.w(TAG, "Could not get process ID", e);
            return -1;
        }
    }

    public boolean isRunning() {
        return mIsRunning && mApiProcess != null && mApiProcess.isAlive();
    }
} 