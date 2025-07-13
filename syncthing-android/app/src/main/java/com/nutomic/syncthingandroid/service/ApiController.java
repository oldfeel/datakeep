package com.nutomic.syncthingandroid.service;

import android.content.Context;
import android.util.Log;

import com.google.gson.Gson;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * HTTP API 服务器，提供与桌面版相同的 REST API 接口
 */
public class ApiController {
    private static final String TAG = "ApiController";
    private static final int PORT = 8080;
    
    private final Context mContext;
    private final RestApi mRestApi;
    private final Gson mGson;
    private ServerSocket mServerSocket;
    private ExecutorService mExecutor;
    private boolean mRunning = false;
    
    public ApiController(Context context, RestApi restApi) {
        mContext = context;
        mRestApi = restApi;
        mGson = new Gson();
    }
    
    public void start() {
        if (mRunning) {
            return;
        }
        
        mRunning = true;
        mExecutor = Executors.newCachedThreadPool();
        
        mExecutor.submit(() -> {
            try {
                mServerSocket = new ServerSocket(PORT);
                Log.i(TAG, "HTTP API 服务器已启动，端口: " + PORT);
                Log.i(TAG, "可用端点:");
                Log.i(TAG, "  GET  /api/devices - 获取设备列表");
                Log.i(TAG, "  GET  /api/device/{deviceId}/folders - 获取设备文件夹");
                Log.i(TAG, "  GET  /api/folder/{folderId} - 获取文件夹文件");
                Log.i(TAG, "  GET  /api/local-device-id - 获取本机设备ID");
                Log.i(TAG, "  GET  /api/wifi-info - 获取WiFi信息");
                Log.i(TAG, "  POST /api/folder/{folderId}/share - 更新文件夹共享");
                Log.i(TAG, "  GET  /api/syncthing/events - 获取Syncthing事件");
                
                while (mRunning) {
                    try {
                        Socket clientSocket = mServerSocket.accept();
                        mExecutor.submit(() -> handleClient(clientSocket));
                    } catch (IOException e) {
                        if (mRunning) {
                            Log.e(TAG, "接受客户端连接失败", e);
                        }
                    }
                }
            } catch (IOException e) {
                Log.e(TAG, "启动 HTTP 服务器失败", e);
            }
        });
    }
    
    public void stop() {
        mRunning = false;
        if (mServerSocket != null) {
            try {
                mServerSocket.close();
            } catch (IOException e) {
                Log.e(TAG, "关闭服务器失败", e);
            }
        }
        if (mExecutor != null) {
            mExecutor.shutdown();
        }
        Log.i(TAG, "HTTP 服务器已停止");
    }
    
    private void handleClient(Socket clientSocket) {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(clientSocket.getInputStream()));
             OutputStream outputStream = clientSocket.getOutputStream()) {
            
            // 读取请求行
            String requestLine = reader.readLine();
            if (requestLine == null) {
                return;
            }
            
            String[] parts = requestLine.split(" ");
            if (parts.length < 2) {
                return;
            }
            
            String method = parts[0];
            String uri = parts[1];
            
            Log.d(TAG, "收到请求: " + method + " " + uri);
            
            // 读取请求头
            Map<String, String> headers = new HashMap<>();
            String line;
            while ((line = reader.readLine()) != null && !line.isEmpty()) {
                if (line.contains(":")) {
                    String[] headerParts = line.split(":", 2);
                    headers.put(headerParts[0].trim(), headerParts[1].trim());
                }
            }
            
            // 处理请求
            String response = handleRequest(method, uri, headers);
            
            // 发送响应
            String httpResponse = "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: application/json\r\n" +
                    "Access-Control-Allow-Origin: *\r\n" +
                    "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n" +
                    "Access-Control-Allow-Headers: Content-Type, Authorization\r\n" +
                    "Content-Length: " + response.getBytes().length + "\r\n" +
                    "\r\n" +
                    response;
            
            outputStream.write(httpResponse.getBytes());
            outputStream.flush();
            
        } catch (IOException e) {
            Log.e(TAG, "处理客户端请求失败", e);
        } finally {
            try {
                clientSocket.close();
            } catch (IOException e) {
                Log.e(TAG, "关闭客户端连接失败", e);
            }
        }
    }
    
    private String handleRequest(String method, String uri, Map<String, String> headers) {
        try {
            // 处理 OPTIONS 预检请求
            if ("OPTIONS".equals(method)) {
                return "";
            }
            
            // 路由处理
            if (uri.startsWith("/api/devices")) {
                return handleDevices();
            } else if (uri.startsWith("/api/device/") && uri.contains("/folders")) {
                return handleDeviceFolders(uri);
            } else if (uri.startsWith("/api/folder/") && !uri.contains("/share")) {
                return handleFolderFiles(uri);
            } else if (uri.equals("/api/local-device-id")) {
                return handleLocalDeviceId();
            } else if (uri.equals("/api/wifi-info")) {
                return handleWifiInfo();
            } else if (uri.startsWith("/api/folder/") && uri.contains("/share")) {
                return handleFolderShare(uri);
            } else if (uri.startsWith("/api/syncthing/events")) {
                return handleSyncthingEvents();
            } else {
                return createErrorResponse("Not Found", 404);
            }
        } catch (Exception e) {
            Log.e(TAG, "处理请求时出错", e);
            return createErrorResponse("Internal Server Error", 500);
        }
    }
    
    private String handleDevices() {
        // 返回模拟的设备列表
        List<Map<String, Object>> devices = new ArrayList<>();
        
        Map<String, Object> localDevice = new HashMap<>();
        localDevice.put("deviceID", "local");
        localDevice.put("name", "Android Device");
        localDevice.put("addresses", new String[]{"dynamic"});
        localDevice.put("isLocal", true);
        devices.add(localDevice);
        
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("data", devices);
        
        return mGson.toJson(response);
    }
    
    private String handleDeviceFolders(String uri) {
        // 从 URI 中提取设备 ID: /api/device/{deviceId}/folders
        String[] parts = uri.split("/");
        if (parts.length >= 4) {
            String deviceId = parts[3];
            
            // 返回模拟的文件夹列表
            List<Map<String, Object>> folders = new ArrayList<>();
            
            Map<String, Object> folder = new HashMap<>();
            folder.put("id", "default");
            folder.put("label", "Documents");
            folder.put("path", "/storage/emulated/0/Documents");
            folder.put("type", "sendreceive");
            folder.put("sharedDevices", new String[]{deviceId});
            folders.add(folder);
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("data", folders);
            
            return mGson.toJson(response);
        }
        return createErrorResponse("Invalid device ID", 400);
    }
    
    private String handleFolderFiles(String uri) {
        // 从 URI 中提取文件夹 ID: /api/folder/{folderId}
        String[] parts = uri.split("/");
        if (parts.length >= 4) {
            String folderId = parts[3];
            
            // 返回模拟的文件列表
            List<Map<String, Object>> files = new ArrayList<>();
            
            Map<String, Object> file = new HashMap<>();
            file.put("name", "example.txt");
            file.put("size", 1024);
            file.put("modified", System.currentTimeMillis());
            file.put("type", "file");
            files.add(file);
            
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("data", files);
            
            return mGson.toJson(response);
        }
        return createErrorResponse("Invalid folder ID", 400);
    }
    
    private String handleLocalDeviceId() {
        // 返回模拟的本机设备ID
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("data", "local");
        
        return mGson.toJson(response);
    }
    
    private String handleWifiInfo() {
        // 返回模拟的 WiFi 信息
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("data", "Android Device WiFi");
        
        return mGson.toJson(response);
    }
    
    private String handleFolderShare(String uri) {
        // 从 URI 中提取文件夹 ID: /api/folder/{folderId}/share
        String[] parts = uri.split("/");
        if (parts.length >= 4) {
            String folderId = parts[3];
            
            // 处理文件夹共享更新
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "文件夹共享已更新");
            
            return mGson.toJson(response);
        }
        return createErrorResponse("Invalid folder ID", 400);
    }
    
    private String handleSyncthingEvents() {
        // 返回模拟的 Syncthing 事件
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("data", new ArrayList<>());
        
        return mGson.toJson(response);
    }
    
    private String createErrorResponse(String message, int statusCode) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        response.put("error", message);
        response.put("statusCode", statusCode);
        return mGson.toJson(response);
    }
} 