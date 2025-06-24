package com.nutomic.syncthingandroid.service;

import android.app.Service;
import android.content.Intent;
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
    
    private Process mApiProcess;
    private Thread mLogThread;
    private boolean mIsRunning = false;

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "MyDataApiService created");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "MyDataApiService started");
        
        if (!mIsRunning) {
            startApiProcess();
        }
        
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

    private void startApiProcess() {
        try {
            // 获取二进制文件路径
            File binaryFile = new File(getApplicationInfo().nativeLibraryDir, BINARY_NAME);
            
            if (!binaryFile.exists()) {
                Log.e(TAG, "API binary not found: " + binaryFile.getAbsolutePath());
                return;
            }

            // 设置可执行权限
            binaryFile.setExecutable(true);

            // 构建命令（参考 SyncthingRunnable）
            String[] command = {
                binaryFile.getAbsolutePath(),
                "-home", getFilesDir().getAbsolutePath(),
                "-no-browser",
                "-logflags=0"
            };

            // 启动进程
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.directory(getFilesDir());
            
            // 设置环境变量
            pb.environment().put("ANDROID_DATA", getFilesDir().getAbsolutePath());
            pb.environment().put("TMPDIR", getCacheDir().getAbsolutePath());
            
            mApiProcess = pb.start();
            mIsRunning = true;

            Log.i(TAG, "API process started with PID: " + getProcessId(mApiProcess));

            // 启动日志监控线程
            startLogMonitoring();

        } catch (IOException e) {
            Log.e(TAG, "Failed to start API process", e);
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