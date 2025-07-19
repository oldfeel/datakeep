package tech.shupi.mydata.util;

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
    private static final String BASE_URL = "https://192.168.2.6:8443"; // 使用真机 IP
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
        
        Request request = new Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .build();
        
        return mClient.newCall(request).execute();
    }
    
    /**
     * 获取设备列表
     */
    public String getDevices() throws IOException {
        Response response = getSync("/api/devices");
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
        Response response = getSync("/api/device/" + deviceId + "/folders");
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
        Response response = getSync("/api/folder/" + folderId);
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
        Response response = getSync("/api/local-device-id");
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
        Response response = getSync("/api/wifi-info");
        if (response.isSuccessful()) {
            String responseBody = response.body().string();
            Log.d(TAG, "WiFi信息响应: " + responseBody);
            return responseBody;
        } else {
            throw new IOException("HTTP 请求失败: " + response.code());
        }
    }
} 