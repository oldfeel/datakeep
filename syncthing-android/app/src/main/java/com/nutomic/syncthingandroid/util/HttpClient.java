package com.nutomic.syncthingandroid.util;

import android.util.Log;

import com.google.gson.Gson;
import com.google.gson.JsonObject;

import java.io.IOException;
import java.security.cert.X509Certificate;
import java.util.concurrent.TimeUnit;

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
    private static final String BASE_URL = "https://localhost:8443"; // 使用 HTTPS
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
     * 异步 GET 请求
     */
    public void get(String endpoint, Callback callback) {
        String url = BASE_URL + endpoint;
        Log.d(TAG, "发送 GET 请求: " + url);
        
        Request request = new Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .build();
        
        mClient.newCall(request).enqueue(callback);
    }
    
    /**
     * 异步 POST 请求
     */
    public void post(String endpoint, JsonObject data, Callback callback) {
        String url = BASE_URL + endpoint;
        Log.d(TAG, "发送 POST 请求: " + url);
        
        RequestBody body = RequestBody.create(mGson.toJson(data), JSON);
        Request request = new Request.Builder()
                .url(url)
                .post(body)
                .addHeader("Content-Type", "application/json")
                .build();
        
        mClient.newCall(request).enqueue(callback);
    }
    
    /**
     * 同步 GET 请求（用于测试）
     */
    public Response getSync(String endpoint) throws IOException {
        String url = BASE_URL + endpoint;
        Log.d(TAG, "发送同步 GET 请求: " + url);
        
        Request request = new Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .build();
        
        return mClient.newCall(request).execute();
    }
    
    /**
     * 获取设备列表
     */
    public void getDevices(Callback callback) {
        get("/api/devices", callback);
    }
    
    /**
     * 获取设备文件夹
     */
    public void getDeviceFolders(String deviceId, Callback callback) {
        get("/api/device/" + deviceId + "/folders", callback);
    }
    
    /**
     * 获取文件夹文件
     */
    public void getFolderFiles(String folderId, Callback callback) {
        get("/api/folder/" + folderId, callback);
    }
    
    /**
     * 获取本机设备ID
     */
    public void getLocalDeviceId(Callback callback) {
        get("/api/local-device-id", callback);
    }
    
    /**
     * 获取WiFi信息
     */
    public void getWifiInfo(Callback callback) {
        get("/api/wifi-info", callback);
    }
    
    /**
     * 更新文件夹共享
     */
    public void updateFolderShare(String folderId, JsonObject shareData, Callback callback) {
        post("/api/folder/" + folderId + "/share", shareData, callback);
    }
    
    /**
     * 获取Syncthing事件
     */
    public void getSyncthingEvents(Callback callback) {
        get("/api/syncthing/events", callback);
    }
} 