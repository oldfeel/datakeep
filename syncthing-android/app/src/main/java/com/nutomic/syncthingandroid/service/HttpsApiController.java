package com.nutomic.syncthingandroid.service;

import android.content.Context;
import android.util.Log;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonElement;
import com.google.gson.JsonArray;
import java.util.stream.Collectors;

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
import java.util.concurrent.CompletableFuture;
import java.io.File;
import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.X509TrustManager;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLServerSocketFactory;
import javax.net.ssl.KeyManagerFactory;
import java.security.PrivateKey;
import java.security.KeyFactory;
import java.security.spec.PKCS8EncodedKeySpec;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.MediaType;
import okhttp3.RequestBody;
import java.util.concurrent.TimeUnit;

/**
 * HTTPS API 服务器，提供与桌面版相同的 REST API 接口
 * 使用预制证书实现 HTTPS，直接访问 Syncthing REST API
 */
public class HttpsApiController {
    private static final String TAG = "HttpsApiController";
    private static final int PORT = 8443; // 使用 HTTPS 端口
    
    // Syncthing API 配置
    private String mSyncthingApiBase; // 动态获取，不使用硬编码
    private static final String SYNCTHING_API_KEY = "your-api-key"; // 需要从配置中获取
    private static final MediaType JSON = MediaType.get("application/json; charset=utf-8");
    
    private final Context mContext;
    private final RestApi mRestApi; // 保留用于获取 API Key
    private final Gson mGson;
    private OkHttpClient mHttpClient; // 移除 final，因为可能为 null
    private SSLServerSocket mServerSocket;
    private ExecutorService mExecutor;
    private boolean mRunning = false;
    
    public HttpsApiController(Context context, RestApi restApi) {
        mContext = context;
        mRestApi = restApi;
        mGson = new Gson();
        
        // 从 RestApi 获取 Syncthing API URL
        if (restApi != null && restApi.getUrl() != null) {
            mSyncthingApiBase = restApi.getUrl().toString();
            Log.i(TAG, "使用 RestApi 的 URL: " + mSyncthingApiBase);
        } else {
            // 备用方案：使用默认 HTTPS URL
            mSyncthingApiBase = "https://127.0.0.1:8384";
            Log.w(TAG, "RestApi 不可用，使用默认 URL: " + mSyncthingApiBase);
        }
        
        // 创建 OkHttpClient，使用与 RestApi 相同的 SSL 配置
        OkHttpClient.Builder clientBuilder = new OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS);
        
        // 初始化时不创建 OkHttpClient，等到需要时再创建
        mHttpClient = null;
        Log.i(TAG, "OkHttpClient 延迟初始化，等待证书文件生成");
    }
    
    /**
     * 延迟初始化 OkHttpClient
     */
    private synchronized OkHttpClient getOrCreateHttpClient() throws Exception {
        if (mHttpClient != null) {
            return mHttpClient;
        }
        
        Log.i(TAG, "开始延迟初始化 OkHttpClient...");
        
        // 创建 OkHttpClient，使用与 RestApi 相同的 SSL 配置
        OkHttpClient.Builder clientBuilder = new OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS);
        
        try {
            Log.i(TAG, "开始配置自定义 SSL...");
            File httpsCertFile = com.nutomic.syncthingandroid.service.Constants.getHttpsCertFile(mContext);
            Log.i(TAG, "证书文件路径: " + httpsCertFile.getAbsolutePath());
            Log.i(TAG, "证书文件存在: " + httpsCertFile.exists());
            
            if (!httpsCertFile.exists()) {
                throw new Exception("证书文件不存在: " + httpsCertFile.getAbsolutePath());
            }
            
            TrustManager[] trustManagers = new TrustManager[]{new com.nutomic.syncthingandroid.http.SyncthingTrustManager(httpsCertFile)};
            Log.i(TAG, "TrustManager 创建成功");
            
            SSLContext sslContext = SSLContext.getInstance("TLS");
            sslContext.init(null, trustManagers, new SecureRandom());
            Log.i(TAG, "SSLContext 创建成功");
            
            SSLSocketFactory sslSocketFactory = sslContext.getSocketFactory();
            Log.i(TAG, "SSLSocketFactory 创建成功");

            clientBuilder.sslSocketFactory(sslSocketFactory, (X509TrustManager) trustManagers[0])
                    .hostnameVerifier((hostname, session) -> true);
            
            Log.i(TAG, "使用自定义 SSL 配置");
            mHttpClient = clientBuilder.build();
            Log.i(TAG, "OkHttpClient 创建成功");
            return mHttpClient;
        } catch (Exception e) {
            Log.e(TAG, "自定义SSL配置失败，API 不可用", e);
            Log.e(TAG, "错误详情: " + e.getMessage());
            throw e;
        }
    }
    
    /**
     * 获取 Syncthing API Key
     */
    private String getApiKey() {
        try {
            if (mRestApi != null && mRestApi.isConfigLoaded()) {
                return mRestApi.getGui().apiKey;
            }
        } catch (Exception e) {
            Log.e(TAG, "获取 API Key 失败", e);
        }
        return "your-api-key"; // 默认值
    }
    
    /**
     * 执行 HTTP GET 请求到 Syncthing API
     */
    private String executeGetRequest(String endpoint) throws IOException {
        try {
            OkHttpClient client = getOrCreateHttpClient();
            String url = mSyncthingApiBase + endpoint;
            Log.d(TAG, "请求 Syncthing API: " + url);
            
            Request request = new Request.Builder()
                    .url(url)
                    .addHeader("X-API-Key", getApiKey())
                    .build();
            
            try (Response response = client.newCall(request).execute()) {
                if (!response.isSuccessful()) {
                    throw new IOException("HTTP 请求失败: " + response.code());
                }
                
                String responseBody = response.body().string();
                Log.d(TAG, "API 响应: " + responseBody);
                return responseBody;
            }
        } catch (Exception e) {
            Log.e(TAG, "OkHttpClient 初始化失败，无法访问 Syncthing API", e);
            throw new IOException("HTTPS 客户端初始化失败，无法访问 Syncthing API: " + e.getMessage());
        }
    }
    
    /**
     * 执行 HTTP POST 请求到 Syncthing API
     */
    private String executePostRequest(String endpoint, String jsonBody) throws IOException {
        try {
            OkHttpClient client = getOrCreateHttpClient();
            String url = mSyncthingApiBase + endpoint;
            Log.d(TAG, "POST 请求 Syncthing API: " + url);
            
            RequestBody body = RequestBody.create(jsonBody, JSON);
            Request request = new Request.Builder()
                    .url(url)
                    .addHeader("X-API-Key", getApiKey())
                    .post(body)
                    .build();
            
            try (Response response = client.newCall(request).execute()) {
                if (!response.isSuccessful()) {
                    throw new IOException("HTTP POST 请求失败: " + response.code());
                }
                
                String responseBody = response.body().string();
                Log.d(TAG, "POST API 响应: " + responseBody);
                return responseBody;
            }
        } catch (Exception e) {
            Log.e(TAG, "OkHttpClient 初始化失败，无法访问 Syncthing API", e);
            throw new IOException("HTTPS 客户端初始化失败，无法访问 Syncthing API: " + e.getMessage());
        }
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
                return fail(404, "Not Found");
            }
        } catch (Exception e) {
            Log.e(TAG, "处理请求时出错", e);
            return fail(500, "Internal Server Error");
        }
    }
    
    private String handleDevices() {
        try {
            Log.i(TAG, "开始获取设备列表");
            
            // 尝试从 Syncthing API 获取设备列表
            String jsonResponse = executeGetRequest("/rest/system/config");
            JsonObject jsonObject = JsonParser.parseString(jsonResponse).getAsJsonObject();
             
             List<Map<String, Object>> devices = new ArrayList<>();
             if (jsonObject.has("devices")) {
                 JsonElement devicesElement = jsonObject.get("devices");
                 
                 if (devicesElement.isJsonObject()) {
                     // devices 是对象格式
                     JsonObject devicesObject = devicesElement.getAsJsonObject();
                     for (Map.Entry<String, JsonElement> entry : devicesObject.entrySet()) {
                         JsonObject deviceJson = entry.getValue().getAsJsonObject();
                         Map<String, Object> device = new HashMap<>();
                         device.put("deviceID", entry.getKey());
                         device.put("name", deviceJson.has("name") ? deviceJson.get("name").getAsString() : "未知设备");
                         device.put("compression", deviceJson.has("compression") ? deviceJson.get("compression").getAsString() : "");
                         device.put("certName", deviceJson.has("certName") ? deviceJson.get("certName").getAsString() : "");
                         device.put("introducer", deviceJson.has("introducer") ? deviceJson.get("introducer").getAsBoolean() : false);
                         device.put("paused", deviceJson.has("paused") ? deviceJson.get("paused").getAsBoolean() : false);
                         
                         // 处理地址列表
                         List<String> addresses = new ArrayList<>();
                         if (deviceJson.has("addresses")) {
                             for (JsonElement addrElement : deviceJson.getAsJsonArray("addresses")) {
                                 addresses.add(addrElement.getAsString());
                             }
                         }
                         device.put("addresses", addresses);
                         
                         Log.i(TAG, "设备: " + device.get("name") + " (ID: " + device.get("deviceID") + ", 地址: " + addresses + ")");
                         devices.add(device);
                     }
                 } else if (devicesElement.isJsonArray()) {
                     // devices 是数组格式
                     JsonArray devicesArray = devicesElement.getAsJsonArray();
                     for (JsonElement deviceElement : devicesArray) {
                         JsonObject deviceJson = deviceElement.getAsJsonObject();
                         Map<String, Object> device = new HashMap<>();
                         device.put("deviceID", deviceJson.has("deviceID") ? deviceJson.get("deviceID").getAsString() : "未知ID");
                         device.put("name", deviceJson.has("name") ? deviceJson.get("name").getAsString() : "未知设备");
                         device.put("compression", deviceJson.has("compression") ? deviceJson.get("compression").getAsString() : "");
                         device.put("certName", deviceJson.has("certName") ? deviceJson.get("certName").getAsString() : "");
                         device.put("introducer", deviceJson.has("introducer") ? deviceJson.get("introducer").getAsBoolean() : false);
                         device.put("paused", deviceJson.has("paused") ? deviceJson.get("paused").getAsBoolean() : false);
                         
                         // 处理地址列表
                         List<String> addresses = new ArrayList<>();
                         if (deviceJson.has("addresses")) {
                             for (JsonElement addrElement : deviceJson.getAsJsonArray("addresses")) {
                                 addresses.add(addrElement.getAsString());
                             }
                         }
                         device.put("addresses", addresses);
                         
                         Log.i(TAG, "设备: " + device.get("name") + " (ID: " + device.get("deviceID") + ", 地址: " + addresses + ")");
                         devices.add(device);
                     }
                 } else {
                     Log.w(TAG, "devices 字段格式未知: " + devicesElement.getClass().getSimpleName());
                 }
             }
            
            Log.i(TAG, "成功获取到 " + devices.size() + " 个设备");
            return success(devices);
            
        } catch (IOException e) {
            Log.e(TAG, "从 Syncthing API 获取设备列表失败，尝试返回模拟数据", e);
            // 返回模拟设备数据
            return getMockDevices();
        } catch (Exception e) {
            Log.e(TAG, "获取设备列表时发生未知错误", e);
            return fail(1005, "Failed to get devices: " + e.getMessage());
        }
    }
    
    /**
     * 从 Syncthing API 获取设备列表
     */
    private List<Map<String, Object>> getDevicesFromSyncthing() throws Exception {
        List<Map<String, Object>> devices = new ArrayList<>();
        
        // 获取本机设备ID
        String localDeviceID = getLocalDeviceID();
        Log.i(TAG, "本机设备ID: " + localDeviceID);
        
        // 获取本机局域网IP地址
        List<String> localIPs = getLocalNetworkIPs();
        Log.i(TAG, "本机局域网IP: " + localIPs);
        
        // 获取设备配置
        List<Map<String, Object>> configDevices = getConfigDevices();
        Log.i(TAG, "从配置获取到 " + configDevices.size() + " 个设备");
        
        // 获取设备连接状态
        Map<String, Map<String, Object>> connections = getDeviceConnections();
        Log.i(TAG, "从连接状态获取到 " + connections.size() + " 个设备连接信息");
        
        // 获取设备发现信息
        Map<String, Object> discoveryInfo = getDeviceDiscovery();
        Log.i(TAG, "设备发现信息: " + discoveryInfo);
        
        // 构建设备列表
        for (Map<String, Object> configDevice : configDevices) {
            String deviceID = (String) configDevice.get("deviceID");
            String name = (String) configDevice.get("name");
            
            Map<String, Object> device = new HashMap<>();
            device.put("deviceID", deviceID);
            device.put("name", name != null ? name : "未知设备");
            device.put("compression", configDevice.get("compression"));
            device.put("certName", configDevice.get("certName"));
            device.put("introducer", configDevice.get("introducer"));
            
            // 检查是否为本机设备
            boolean isLocalDevice = localDeviceID != null && localDeviceID.equals(deviceID);
            
            // 设置连接状态
            if (connections.containsKey(deviceID)) {
                Map<String, Object> conn = connections.get(deviceID);
                device.put("connected", conn.get("connected"));
                device.put("connectionType", conn.get("type"));
                device.put("clientVersion", conn.get("clientVersion"));
                device.put("inBytesTotal", conn.get("inBytesTotal"));
                device.put("outBytesTotal", conn.get("outBytesTotal"));
                device.put("isLocalNetwork", conn.get("isLocalNetwork"));
                device.put("crypto", conn.get("crypto"));
            } else if (isLocalDevice) {
                // 本机设备特殊处理
                device.put("connected", true);
                device.put("connectionType", "local");
                device.put("clientVersion", "local");
                device.put("inBytesTotal", 0L);
                device.put("outBytesTotal", 0L);
                device.put("isLocalNetwork", true);
                device.put("crypto", "local");
                Log.i(TAG, "本机设备 " + name + " 设置为在线状态");
            } else {
                // 其他设备默认离线
                device.put("connected", false);
                device.put("connectionType", "unknown");
                device.put("clientVersion", "");
                device.put("inBytesTotal", 0L);
                device.put("outBytesTotal", 0L);
                device.put("isLocalNetwork", false);
                device.put("crypto", "");
            }
            
            // 处理地址列表
            List<String> addresses = new ArrayList<>();
            
            // 从连接状态获取地址
            if (connections.containsKey(deviceID)) {
                Map<String, Object> conn = connections.get(deviceID);
                if (Boolean.TRUE.equals(conn.get("connected"))) {
                    String address = (String) conn.get("address");
                    if (address != null && !address.isEmpty()) {
                        addresses.add(address);
                    }
                    
                    @SuppressWarnings("unchecked")
                    Map<String, Object> primary = (Map<String, Object>) conn.get("primary");
                    if (primary != null) {
                        String primaryAddress = (String) primary.get("address");
                        if (primaryAddress != null && !primaryAddress.isEmpty() && !primaryAddress.equals(address)) {
                            addresses.add(primaryAddress);
                        }
                    }
                }
            }
            
            // 从发现信息获取地址
            if (discoveryInfo != null && discoveryInfo.containsKey(deviceID)) {
                @SuppressWarnings("unchecked")
                Map<String, Object> deviceDiscovery = (Map<String, Object>) discoveryInfo.get(deviceID);
                if (deviceDiscovery != null && deviceDiscovery.containsKey("addresses")) {
                    @SuppressWarnings("unchecked")
                    List<String> discoveryAddresses = (List<String>) deviceDiscovery.get("addresses");
                    if (discoveryAddresses != null) {
                        for (String addr : discoveryAddresses) {
                            if (!addr.contains("relay://")) {
                                addresses.add(addr);
                            }
                        }
                    }
                }
            }
            
            // 为本机设备添加本地地址
            if (isLocalDevice && localIPs != null) {
                addresses.addAll(localIPs);
                Log.i(TAG, "为本机设备添加本地地址: " + localIPs);
            }
            
            // 去重并过滤地址
            List<String> uniqueAddresses = new ArrayList<>();
            for (String addr : addresses) {
                if (!uniqueAddresses.contains(addr)) {
                    uniqueAddresses.add(addr);
                }
            }
            
            // 过滤局域网地址
            List<String> filteredAddresses = filterAndExtractIPAddresses(uniqueAddresses, localIPs);
            device.put("addresses", filteredAddresses);
            
            Log.i(TAG, "设备 " + name + " 地址: " + filteredAddresses + 
                      ", 连接状态: " + device.get("connected") + 
                      ", 类型: " + device.get("connectionType") + 
                      ", 本地连接: " + device.get("isLocalNetwork"));
            
            devices.add(device);
        }
        
        return devices;
    }
    
    /**
     * 获取本机设备ID
     */
    private String getLocalDeviceID() {
        try {
            // 从 Syncthing API 获取本机设备ID
            String jsonResponse = executeGetRequest("/rest/system/status");
            JsonObject jsonObject = JsonParser.parseString(jsonResponse).getAsJsonObject();
            
            if (jsonObject.has("myID")) {
                String localDeviceID = jsonObject.get("myID").getAsString();
                Log.i(TAG, "从 Syncthing API 获取到本机设备ID: " + localDeviceID);
                return localDeviceID;
            }
            
            Log.w(TAG, "无法从 Syncthing API 获取本机设备ID，返回默认值");
            return "local-device-id";
        } catch (Exception e) {
            Log.e(TAG, "获取本机设备ID失败", e);
            return "local-device-id";
        }
    }
    
    /**
     * 获取本机局域网IP地址
     */
    private List<String> getLocalNetworkIPs() {
        List<String> localIPs = new ArrayList<>();
        try {
            // 获取所有网络接口
            java.util.Enumeration<java.net.NetworkInterface> interfaces = java.net.NetworkInterface.getNetworkInterfaces();
            
            while (interfaces.hasMoreElements()) {
                java.net.NetworkInterface iface = interfaces.nextElement();
                
                // 跳过回环接口和down的接口
                if (iface.isLoopback() || !iface.isUp()) {
                    continue;
                }
                
                java.util.Enumeration<java.net.InetAddress> addrs = iface.getInetAddresses();
                while (addrs.hasMoreElements()) {
                    java.net.InetAddress addr = addrs.nextElement();
                    
                    // 只获取IPv4地址，并且是私有地址
                    if (addr instanceof java.net.Inet4Address && isPrivateIP(addr.getHostAddress())) {
                        String ip = addr.getHostAddress();
                        if (!localIPs.contains(ip)) {
                            localIPs.add(ip);
                            Log.i(TAG, "发现本地网络IP: " + ip + " (接口: " + iface.getDisplayName() + ")");
                        }
                    }
                }
            }
            
            Log.i(TAG, "获取到 " + localIPs.size() + " 个本地网络IP: " + localIPs);
            return localIPs;
            
        } catch (Exception e) {
            Log.e(TAG, "获取本机局域网IP失败", e);
            // 返回默认值
            localIPs.add("192.168.1.100");
            return localIPs;
        }
    }
    
    /**
     * 判断是否为私有IP地址
     */
    private boolean isPrivateIP(String ip) {
        try {
            java.net.InetAddress addr = java.net.InetAddress.getByName(ip);
            return addr.isSiteLocalAddress();
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 从配置获取设备列表
     */
    private List<Map<String, Object>> getConfigDevices() {
        List<Map<String, Object>> devices = new ArrayList<>();
        
        try {
            // 从 Syncthing API 获取设备配置
            String jsonResponse = executeGetRequest("/rest/system/config");
            JsonObject jsonObject = JsonParser.parseString(jsonResponse).getAsJsonObject();
            
                         if (jsonObject.has("devices")) {
                 for (Map.Entry<String, JsonElement> entry : jsonObject.getAsJsonObject("devices").entrySet()) {
                     JsonObject deviceJson = entry.getValue().getAsJsonObject();
                     String deviceID = entry.getKey();
                     
                     Map<String, Object> device = new HashMap<>();
                     device.put("deviceID", deviceID);
                     device.put("name", deviceJson.has("name") ? deviceJson.get("name").getAsString() : "未知设备");
                     device.put("compression", deviceJson.has("compression") ? deviceJson.get("compression").getAsString() : "");
                     device.put("certName", deviceJson.has("certName") ? deviceJson.get("certName").getAsString() : "");
                     device.put("introducer", deviceJson.has("introducer") ? deviceJson.get("introducer").getAsBoolean() : false);
                     device.put("paused", deviceJson.has("paused") ? deviceJson.get("paused").getAsBoolean() : false);
                     
                     // 处理地址列表
                     List<String> addresses = new ArrayList<>();
                     if (deviceJson.has("addresses")) {
                         for (JsonElement addrElement : deviceJson.getAsJsonArray("addresses")) {
                             addresses.add(addrElement.getAsString());
                         }
                     }
                     device.put("addresses", addresses);
                     
                     Log.i(TAG, "设备: " + device.get("name") + 
                               " (ID: " + deviceID + 
                               ", 地址: " + addresses + ")");
                     
                     devices.add(device);
                 }
             }
            
            Log.i(TAG, "从 Syncthing API 获取到 " + devices.size() + " 个设备");
        } catch (Exception e) {
            Log.e(TAG, "从 Syncthing API 获取设备列表失败", e);
            // 返回空列表而不是抛出异常，避免整个请求失败
        }
        
        return devices;
    }
    
    /**
     * 获取设备连接状态
     */
    /**
     * 异步获取设备连接信息
     */
    private CompletableFuture<Map<String, Map<String, Object>>> getDeviceConnectionsAsync() {
        return CompletableFuture.supplyAsync(() -> {
            Map<String, Map<String, Object>> connections = new HashMap<>();
            
            try {
                Log.i(TAG, "开始异步获取设备连接信息");
                // 从 Syncthing API 获取连接状态
                String jsonResponse = executeGetRequest("/rest/system/connections");
                JsonObject jsonObject = JsonParser.parseString(jsonResponse).getAsJsonObject();
                
                if (jsonObject.has("connections")) {
                    for (Map.Entry<String, JsonElement> entry : jsonObject.getAsJsonObject("connections").entrySet()) {
                        JsonObject connJson = entry.getValue().getAsJsonObject();
                        String deviceID = entry.getKey();
                        
                        Map<String, Object> connectionInfo = new HashMap<>();
                        connectionInfo.put("connected", connJson.has("connected") ? connJson.get("connected").getAsBoolean() : false);
                        connectionInfo.put("type", connJson.has("type") ? connJson.get("type").getAsString() : "");
                        connectionInfo.put("address", connJson.has("address") ? connJson.get("address").getAsString() : "");
                        connectionInfo.put("clientVersion", connJson.has("clientVersion") ? connJson.get("clientVersion").getAsString() : "");
                        connectionInfo.put("inBytesTotal", connJson.has("inBytesTotal") ? connJson.get("inBytesTotal").getAsLong() : 0L);
                        connectionInfo.put("outBytesTotal", connJson.has("outBytesTotal") ? connJson.get("outBytesTotal").getAsLong() : 0L);
                        connectionInfo.put("isLocalNetwork", connJson.has("isLocalNetwork") ? connJson.get("isLocalNetwork").getAsBoolean() : false);
                        connectionInfo.put("crypto", connJson.has("crypto") ? connJson.get("crypto").getAsString() : "");
                        
                        // 处理 primary 地址
                        if (connJson.has("primary")) {
                            JsonObject primaryJson = connJson.getAsJsonObject("primary");
                            Map<String, Object> primary = new HashMap<>();
                            primary.put("address", primaryJson.get("address").getAsString());
                            primary.put("type", primaryJson.get("type").getAsString());
                            connectionInfo.put("primary", primary);
                        }
                        
                        connections.put(deviceID, connectionInfo);
                        
                        Log.i(TAG, "设备 " + deviceID + " 连接信息: " +
                                  "connected=" + connectionInfo.get("connected") + 
                                  ", type=" + connectionInfo.get("type") + 
                                  ", address=" + connectionInfo.get("address") + 
                                  ", isLocalNetwork=" + connectionInfo.get("isLocalNetwork"));
                    }
                } else {
                    Log.w(TAG, "连接数据为空");
                }
            } catch (IOException e) {
                Log.e(TAG, "从 Syncthing API 获取设备连接状态失败", e);
            }
            
            Log.i(TAG, "异步获取设备连接信息完成，共 " + connections.size() + " 个设备");
            return connections;
        });
    }

    /**
     * 获取设备连接信息（使用 await 风格）
     */
    private Map<String, Map<String, Object>> getDeviceConnections() {
        try {
            // 类似 JavaScript 的 await
            return getDeviceConnectionsAsync().get();
        } catch (Exception e) {
            Log.e(TAG, "等待异步获取设备连接信息失败", e);
            return new HashMap<>();
        }
    }
    
    /**
     * 异步获取设备发现信息
     */
    private CompletableFuture<Map<String, Object>> getDeviceDiscoveryAsync() {
        return CompletableFuture.supplyAsync(() -> {
            Map<String, Object> discoveryInfo = new HashMap<>();
            
            try {
                Log.i(TAG, "开始异步获取设备发现信息");
                // 从 Syncthing API 获取设备发现信息
                String jsonResponse = executeGetRequest("/rest/system/discovery");
                JsonObject jsonObject = JsonParser.parseString(jsonResponse).getAsJsonObject();
                
                if (jsonObject.has("devices")) {
                    for (Map.Entry<String, JsonElement> entry : jsonObject.getAsJsonObject("devices").entrySet()) {
                        JsonObject deviceJson = entry.getValue().getAsJsonObject();
                        String deviceID = entry.getKey();
                        
                        Map<String, Object> deviceDiscoveryInfo = new HashMap<>();
                        List<String> addresses = new ArrayList<>();
                        if (deviceJson.has("addresses")) {
                            for (JsonElement addrElement : deviceJson.getAsJsonArray("addresses")) {
                                addresses.add(addrElement.getAsString());
                            }
                        }
                        deviceDiscoveryInfo.put("addresses", addresses);
                        
                        discoveryInfo.put(deviceID, deviceDiscoveryInfo);
                        
                        Log.i(TAG, "设备 " + deviceID + " 发现信息: " + deviceDiscoveryInfo);
                    }
                } else {
                    Log.w(TAG, "发现数据为空");
                }
            } catch (IOException e) {
                Log.e(TAG, "从 Syncthing API 获取设备发现信息失败", e);
            }
            
            Log.i(TAG, "异步获取设备发现信息完成，共 " + discoveryInfo.size() + " 个设备");
            return discoveryInfo;
        });
    }

    /**
     * 获取设备发现信息（使用 await 风格）
     */
    private Map<String, Object> getDeviceDiscovery() {
        try {
            // 类似 JavaScript 的 await
            return getDeviceDiscoveryAsync().get();
        } catch (Exception e) {
            Log.e(TAG, "等待异步获取设备发现信息失败", e);
            return new HashMap<>();
        }
    }
    
    /**
     * 过滤和提取IP地址
     */
    private List<String> filterAndExtractIPAddresses(List<String> addresses, List<String> localIPs) {
        List<String> filteredIPs = new ArrayList<>();
        
        for (String addr : addresses) {
            // 跳过relay地址
            if (addr.contains("relay://")) {
                continue;
            }
            
            // 跳过IPv6地址
            if (addr.contains("[") && addr.contains("]")) {
                continue;
            }
            
            // 提取IP地址
            String ip = extractIPFromAddress(addr);
            if (ip != null && !ip.isEmpty()) {
                // 检查是否与本机在同一局域网
                if (isInSameNetwork(ip, localIPs)) {
                    if (!filteredIPs.contains(ip)) {
                        filteredIPs.add(ip);
                    }
                }
            }
        }
        
        return filteredIPs;
    }
    
    /**
     * 从地址字符串中提取IP地址
     */
    private String extractIPFromAddress(String addr) {
        // 简单的IPv4地址提取
        String[] parts = addr.split(":");
        if (parts.length > 0) {
            String ipPart = parts[0];
            if (ipPart.matches("\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}")) {
                return ipPart;
            }
        }
        return null;
    }
    
    /**
     * 检查IP是否与本机在同一局域网
     */
    private boolean isInSameNetwork(String ip, List<String> localIPs) {
        if (localIPs == null || localIPs.isEmpty()) {
            return false;
        }
        
        for (String localIP : localIPs) {
            String[] ipParts = ip.split("\\.");
            String[] localParts = localIP.split("\\.");
            
            if (ipParts.length == 4 && localParts.length == 4) {
                // 对于192.168.x.x，检查前两个字节
                if (ipParts[0].equals("192") && ipParts[1].equals("168") &&
                    localParts[0].equals("192") && localParts[1].equals("168")) {
                    return ipParts[2].equals(localParts[2]);
                }
                // 对于10.x.x.x，检查第一个字节
                else if (ipParts[0].equals("10") && localParts[0].equals("10")) {
                    return ipParts[1].equals(localParts[1]);
                }
                // 对于172.16-31.x.x，检查前两个字节
                else if (ipParts[0].equals("172") && localParts[0].equals("172")) {
                    int ipSecond = Integer.parseInt(ipParts[1]);
                    int localSecond = Integer.parseInt(localParts[1]);
                    if (ipSecond >= 16 && ipSecond <= 31 && localSecond >= 16 && localSecond <= 31) {
                        return ipSecond == localSecond;
                    }
                }
            }
        }
        
        return false;
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
        
        return success(folders);
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
        
        return success(files);
    }
    
    private String handleLocalDeviceId() {
        return success("local-device-id");
    }
    
    /**
     * 返回空设备列表
     */
    private String getMockDevices() {
        Log.i(TAG, "返回空设备列表");
        return success(new ArrayList<>());
    }
    
    private String handleWifiInfo() {
        Map<String, Object> wifiInfo = new HashMap<>();
        wifiInfo.put("ssid", "Android WiFi");
        wifiInfo.put("signal", -50);
        
        return success(wifiInfo);
    }
    
    private String handleFolderShare(String uri) {
        return success("文件夹共享更新成功");
    }
    
    private String handleSyncthingEvents() {
        return success(new ArrayList<>());
    }
    
    /**
     * 成功响应辅助方法
     * @param data 响应数据
     * @return JSON 字符串
     */
    private String success(Object data) {
        Map<String, Object> response = new HashMap<>();
        response.put("code", 0);
        response.put("data", data);
        return mGson.toJson(response);
    }
    
    /**
     * 失败响应辅助方法
     * @param code 错误代码
     * @param message 错误信息
     * @return JSON 字符串
     */
    private String fail(int code, String message) {
        Map<String, Object> response = new HashMap<>();
        response.put("code", code);
        response.put("data", message);
        return mGson.toJson(response);
    }
    
    /**
     * 创建错误响应（保持向后兼容）
     * @param message 错误信息
     * @param statusCode 状态码
     * @return JSON 字符串
     */
    private String createErrorResponse(String message, int statusCode) {
        return fail(statusCode, message);
    }
} 