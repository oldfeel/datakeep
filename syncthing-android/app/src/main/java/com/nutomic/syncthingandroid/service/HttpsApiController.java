package com.nutomic.syncthingandroid.service;

import android.content.Context;
import android.util.Log;

import com.google.gson.Gson;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLServerSocketFactory;
import javax.net.ssl.KeyManagerFactory;
import java.security.PrivateKey;
import java.security.KeyFactory;
import java.security.spec.PKCS8EncodedKeySpec;

/**
 * HTTPS API 服务器，提供与桌面版相同的 REST API 接口
 * 使用预制证书实现 HTTPS
 */
public class HttpsApiController {
    private static final String TAG = "HttpsApiController";
    private static final int PORT = 8443; // 使用 HTTPS 端口
    
    private final Context mContext;
    private final RestApi mRestApi;
    private final Gson mGson;
    private SSLServerSocket mServerSocket;
    private ExecutorService mExecutor;
    private boolean mRunning = false;
    
    public HttpsApiController(Context context, RestApi restApi) {
        mContext = context;
        mRestApi = restApi;
        mGson = new Gson();
    }
    
    public void start() {
        if (mRunning) {
            Log.w(TAG, "HTTPS 服务器已经在运行");
            return;
        }
        
        Log.i(TAG, "开始启动 HTTPS 服务器...");
        mRunning = true;
        mExecutor = Executors.newCachedThreadPool();
        
        mExecutor.submit(() -> {
            try {
                Log.i(TAG, "正在创建 SSL 服务器套接字...");
                mServerSocket = createSslServerSocket(PORT);
                Log.i(TAG, "SSL 服务器套接字创建成功");
                Log.i(TAG, "HTTPS API 服务器已启动，端口: " + PORT);
                Log.i(TAG, "服务器地址: https://localhost:" + PORT);
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
                        Log.d(TAG, "等待客户端连接...");
                        Socket clientSocket = mServerSocket.accept();
                        Log.d(TAG, "接受客户端连接: " + clientSocket.getInetAddress());
                        mExecutor.submit(() -> handleClient(clientSocket));
                    } catch (IOException e) {
                        if (mRunning) {
                            Log.e(TAG, "接受客户端连接失败", e);
                        }
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "启动 HTTPS 服务器失败", e);
                mRunning = false;
            }
        });
    }
    
    /**
     * 创建 SSL 服务器套接字，使用预制证书
     */
    private SSLServerSocket createSslServerSocket(int port) throws Exception {
        Log.i(TAG, "开始创建 SSL 服务器套接字，端口: " + port);
        
        // 1. 加载预制证书和私钥
        Log.i(TAG, "正在加载预制证书...");
        X509Certificate cert = loadCertificate();
        if (cert == null) {
            throw new Exception("预制证书加载失败");
        }
        Log.i(TAG, "预制证书加载成功");
        
        Log.i(TAG, "正在加载预制私钥...");
        PrivateKey privateKey = loadPrivateKey();
        if (privateKey == null) {
            throw new Exception("预制私钥加载失败");
        }
        Log.i(TAG, "预制私钥加载成功");
        
        // 2. 放入 KeyStore
        Log.i(TAG, "正在创建 KeyStore...");
        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        keyStore.load(null, null);
        keyStore.setKeyEntry("alias", privateKey, "password".toCharArray(), new Certificate[]{cert});
        Log.i(TAG, "KeyStore 创建成功");

        // 3. KeyManager
        Log.i(TAG, "正在创建 KeyManager...");
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(keyStore, "password".toCharArray());
        Log.i(TAG, "KeyManager 创建成功");

        // 4. SSLContext
        Log.i(TAG, "正在创建 SSLContext...");
        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(kmf.getKeyManagers(), null, null);
        Log.i(TAG, "SSLContext 创建成功");

        // 5. 创建 SSLServerSocket
        Log.i(TAG, "正在创建 SSLServerSocket...");
        SSLServerSocketFactory ssf = sslContext.getServerSocketFactory();
        SSLServerSocket serverSocket = (SSLServerSocket) ssf.createServerSocket(port);
        serverSocket.setEnabledProtocols(new String[]{"TLSv1.2"});
        Log.i(TAG, "SSLServerSocket 创建成功");
        
        return serverSocket;
    }
    
    /**
     * 加载预制证书
     */
    private X509Certificate loadCertificate() {
        try {
            // 从 assets 目录加载证书
            InputStream certStream = mContext.getAssets().open("certificate.crt");
            CertificateFactory certFactory = CertificateFactory.getInstance("X.509");
            X509Certificate cert = (X509Certificate) certFactory.generateCertificate(certStream);
            certStream.close();
            Log.i(TAG, "预制证书加载成功");
            return cert;
        } catch (Exception e) {
            Log.e(TAG, "加载预制证书失败", e);
            return null;
        }
    }
    
    /**
     * 加载预制私钥
     */
    private PrivateKey loadPrivateKey() {
        try {
            // 从 assets 目录加载私钥
            InputStream keyStream = mContext.getAssets().open("private.key");
            byte[] keyBytes = new byte[keyStream.available()];
            keyStream.read(keyBytes);
            keyStream.close();
            
            // 解析 PEM 格式的私钥
            String pemKey = new String(keyBytes);
            
            // 移除 PEM 头尾和换行符
            String privateKeyPEM = pemKey
                    .replace("-----BEGIN PRIVATE KEY-----", "")
                    .replace("-----END PRIVATE KEY-----", "")
                    .replaceAll("\\s", "");
            
            // Base64 解码
            byte[] decodedKey = java.util.Base64.getDecoder().decode(privateKeyPEM);
            
            // 解析 PKCS8 格式的私钥
            PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(decodedKey);
            KeyFactory keyFactory = KeyFactory.getInstance("RSA");
            PrivateKey privateKey = keyFactory.generatePrivate(keySpec);
            
            Log.i(TAG, "预制私钥加载成功");
            return privateKey;
        } catch (Exception e) {
            Log.e(TAG, "加载预制私钥失败", e);
            return null;
        }
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
        Log.i(TAG, "HTTPS 服务器已停止");
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
            
            Log.d(TAG, "收到 HTTP 请求: " + method + " " + uri);
            
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
        response.put("devices", devices);
        
        return mGson.toJson(response);
    }
    
    private String handleDeviceFolders(String uri) {
        // 解析设备ID
        String deviceId = uri.substring("/api/device/".length(), uri.indexOf("/folders"));
        
        // 返回模拟的文件夹列表
        List<Map<String, Object>> folders = new ArrayList<>();
        
        Map<String, Object> folder = new HashMap<>();
        folder.put("id", "default");
        folder.put("label", "默认文件夹");
        folder.put("path", "/storage/emulated/0/Syncthing");
        folder.put("type", "sendreceive");
        folders.add(folder);
        
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("folders", folders);
        
        return mGson.toJson(response);
    }
    
    private String handleFolderFiles(String uri) {
        // 解析文件夹ID
        String folderId = uri.substring("/api/folder/".length());
        
        // 返回模拟的文件列表
        List<Map<String, Object>> files = new ArrayList<>();
        
        Map<String, Object> file = new HashMap<>();
        file.put("name", "test.txt");
        file.put("size", 1024);
        file.put("type", "file");
        files.add(file);
        
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("files", files);
        
        return mGson.toJson(response);
    }
    
    private String handleLocalDeviceId() {
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("deviceID", "local-device-id");
        return mGson.toJson(response);
    }
    
    private String handleWifiInfo() {
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("ssid", "Android WiFi");
        response.put("signal", -50);
        return mGson.toJson(response);
    }
    
    private String handleFolderShare(String uri) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("message", "文件夹共享更新成功");
        return mGson.toJson(response);
    }
    
    private String handleSyncthingEvents() {
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("events", new ArrayList<>());
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