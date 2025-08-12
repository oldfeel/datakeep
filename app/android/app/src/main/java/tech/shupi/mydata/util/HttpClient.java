package tech.shupi.mydata.util;

import android.util.Log;

import com.google.gson.Gson;
import com.google.gson.JsonObject;

import java.io.IOException;
import java.io.File;
import java.security.cert.X509Certificate;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import java.util.regex.Matcher;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

/**
 * HTTP 客户端工具类，支持 HTTPS 和自签名证书
 */
public class HttpClient {
    private static final String TAG = "HttpClient";
    private static final String BASE_URL = "http://127.0.0.1:8384"; // 直接调用 Syncthing API
    private static final MediaType JSON = MediaType.get("application/json; charset=utf-8");
    
    private final OkHttpClient mClient;
    private final Gson mGson;
    
    public HttpClient() {
        mGson = new Gson();
        
        // 创建信任所有证书的 TrustManager（仅用于开发环境）
        TrustManager[] trustAllCerts = new TrustManager[]{
            new X509TrustManager() {
                @Override
                public void checkClientTrusted(X509Certificate[] chain, String authType) {
                }
                
                @Override
                public void checkServerTrusted(X509Certificate[] chain, String authType) {
                }
                
                @Override
                public X509Certificate[] getAcceptedIssuers() {
                    return new X509Certificate[0];
                }
            }
        };
        
        OkHttpClient.Builder builder = new OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS);
        
        try {
            // 创建 SSL 上下文
            SSLContext sslContext = SSLContext.getInstance("TLS");
            sslContext.init(null, trustAllCerts, new java.security.SecureRandom());
            
            // 配置 OkHttpClient 支持 SSL
            builder.sslSocketFactory(sslContext.getSocketFactory(), (X509TrustManager) trustAllCerts[0])
                   .hostnameVerifier((hostname, session) -> true); // 信任所有主机名
            
            Log.d(TAG, "SSL 客户端配置成功");
        } catch (Exception e) {
            Log.e(TAG, "创建 SSL 客户端失败，使用普通 HTTP 客户端", e);
        }
        
        mClient = builder.build();
    }
    
    /**
     * 同步 GET 请求
     */
    public Response getSync(String endpoint) throws IOException {
        String url = BASE_URL + endpoint;
        Log.d(TAG, "发送同步 GET 请求: " + url);
        
        // 获取 API Key
        String apiKey = getApiKeyFromConfig();
        Log.d(TAG, "使用 API Key: " + (apiKey != null ? apiKey.substring(0, Math.min(8, apiKey.length())) + "..." : "null"));
        
        Request.Builder requestBuilder = new Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json");
        
        // 添加 API Key 认证
        if (apiKey != null && !apiKey.isEmpty()) {
            requestBuilder.addHeader("X-API-Key", apiKey);
        }
        
        Request request = requestBuilder.build();
        
        return mClient.newCall(request).execute();
    }
    
    /**
     * 获取设备列表
     */
    public String getDevices() throws IOException {
        Response response = getSync("/rest/config/devices");
        if (response.isSuccessful()) {
            String responseBody = response.body().string();
            Log.d(TAG, "设备列表响应: " + responseBody);
            return responseBody;
        } else {
            throw new IOException("HTTP 请求失败: " + response.code());
        }
    }
    
    /**
     * 获取设备文件夹
     */
    public String getDeviceFolders(String deviceId) throws IOException {
        Response response = getSync("/rest/config/folders");
        if (response.isSuccessful()) {
            String responseBody = response.body().string();
            Log.d(TAG, "设备文件夹响应: " + responseBody);
            return responseBody;
        } else {
            throw new IOException("HTTP 请求失败: " + response.code());
        }
    }
    
    /**
     * 获取文件夹文件
     */
    public String getFolderFiles(String folderId) throws IOException {
        Response response = getSync("/rest/db/browse?folder=" + folderId);
        if (response.isSuccessful()) {
            String responseBody = response.body().string();
            Log.d(TAG, "文件夹文件响应: " + responseBody);
            return responseBody;
        } else {
            throw new IOException("HTTP 请求失败: " + response.code());
        }
    }
    
    /**
     * 获取本机设备ID
     */
    public String getLocalDeviceId() throws IOException {
        Response response = getSync("/rest/system/status");
        if (response.isSuccessful()) {
            String responseBody = response.body().string();
            Log.d(TAG, "本机设备ID响应: " + responseBody);
            return responseBody;
        } else {
            throw new IOException("HTTP 请求失败: " + response.code());
        }
    }
    
    /**
     * 获取WiFi信息
     */
    public String getWifiInfo() throws IOException {
        // 这个端点在 Syncthing 中不存在，返回本地网络信息
        // 或者可以调用 /rest/system/connections 获取连接信息
        Response response = getSync("/rest/system/connections");
        if (response.isSuccessful()) {
            String responseBody = response.body().string();
            Log.d(TAG, "WiFi信息响应: " + responseBody);
            return responseBody;
        } else {
            throw new IOException("HTTP 请求失败: " + response.code());
        }
    }
    
    /**
     * 获取附近发现的设备
     */
    public String getNearbyDevices() throws IOException {
        Response response = getSync("/rest/system/discovery");
        if (response.isSuccessful()) {
            String responseBody = response.body().string();
            Log.d(TAG, "附近设备响应: " + responseBody);
            return responseBody;
        } else {
            throw new IOException("HTTP 请求失败: " + response.code());
        }
    }
    
    /**
     * 添加设备
     */
    public String addDevice(String deviceConfig) throws IOException {
        Log.d(TAG, "开始添加设备，配置: " + deviceConfig);
        
        String url = BASE_URL + "/rest/config/devices";
        Log.d(TAG, "发送 POST 请求: " + url);
        
        // 获取 API Key
        String apiKey = getApiKeyFromConfig();
        Log.d(TAG, "使用 API Key: " + (apiKey != null ? apiKey.substring(0, Math.min(8, apiKey.length())) + "..." : "null"));
        
        RequestBody requestBody = RequestBody.create(deviceConfig, JSON);
        
        Request.Builder requestBuilder = new Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .post(requestBody);
        
        // 添加 API Key 认证
        if (apiKey != null && !apiKey.isEmpty()) {
            requestBuilder.addHeader("X-API-Key", apiKey);
        }
        
        Request request = requestBuilder.build();
        
        Response response = mClient.newCall(request).execute();
        if (response.isSuccessful()) {
            String responseBody = response.body().string();
            Log.d(TAG, "添加设备响应: " + responseBody);
            return responseBody;
        } else {
            throw new IOException("添加设备失败: " + response.code());
        }
    }
    
    /**
     * 从 Syncthing 配置文件获取 API Key
     */
    private String getApiKeyFromConfig() {
        Log.d(TAG, "尝试从 Syncthing 配置文件获取 API Key");
        
        // 主要配置文件路径
        String configPath = "/data/data/tech.shupi.mydata/files/config.xml";
        
        try {
            File file = new File(configPath);
            if (file.exists()) {
                Log.d(TAG, "找到配置文件: " + configPath);
                
                // 读取文件内容
                String content = new String(java.nio.file.Files.readAllBytes(file.toPath()));
                
                // 简单的 XML 解析，查找 apikey 标签
                Pattern apiKeyPattern = Pattern.compile("<apikey>([^<]+)</apikey>");
                Matcher matchResult = apiKeyPattern.matcher(content);
                
                if (matchResult.find()) {
                    String apiKey = matchResult.group(1);
                    if (apiKey != null && !apiKey.isEmpty()) {
                        Log.d(TAG, "成功从配置文件获取 API Key: " + apiKey.substring(0, Math.min(8, apiKey.length())) + "...");
                        return apiKey;
                    } else {
                        Log.w(TAG, "配置文件中的 API Key 为空");
                    }
                } else {
                    Log.w(TAG, "配置文件中未找到 apikey 标签");
                }
            } else {
                Log.e(TAG, "配置文件不存在: " + configPath);
            }
        } catch (Exception e) {
            Log.e(TAG, "读取配置文件失败: " + configPath, e);
        }
        
        // 如果获取失败，返回 null
        Log.e(TAG, "无法从配置文件获取有效的 API Key: " + configPath);
        return null;
    }
}
