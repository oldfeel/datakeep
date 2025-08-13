package tech.shupi.mydata.util;

import android.util.Log;

import com.google.gson.Gson;
import com.google.gson.JsonObject;

import tech.shupi.mydata.model.Device;
import tech.shupi.mydata.model.ConnectionInfo;
import tech.shupi.mydata.model.DiscoveryInfo;

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
        Log.d(TAG, "开始获取设备列表...");
        
        // 1. 获取设备配置
        Response configResponse = getSync("/rest/config/devices");
        if (!configResponse.isSuccessful()) {
            throw new IOException("获取设备配置失败: " + configResponse.code());
        }
        String devicesConfig = configResponse.body().string();
        Log.d(TAG, "设备配置响应: " + devicesConfig);
        
        // 2. 获取设备连接状态
        String connectionsInfo = "";
        try {
            Response connectionsResponse = getSync("/rest/system/connections");
            if (connectionsResponse.isSuccessful()) {
                connectionsInfo = connectionsResponse.body().string();
                Log.d(TAG, "设备连接状态响应: " + connectionsInfo);
            }
        } catch (Exception e) {
            Log.w(TAG, "获取设备连接状态失败，继续处理: " + e.getMessage());
        }
        
        // 3. 获取设备发现信息
        String discoveryInfo = "";
        try {
            Response discoveryResponse = getSync("/rest/system/discovery");
            if (discoveryResponse.isSuccessful()) {
                discoveryInfo = discoveryResponse.body().string();
                Log.d(TAG, "设备发现信息响应: " + discoveryInfo);
            }
        } catch (Exception e) {
            Log.w(TAG, "获取设备发现信息失败，继续处理: " + e.getMessage());
        }
        
        // 4. 获取本机设备ID
        String localDeviceId = "";
        try {
            Response statusResponse = getSync("/rest/system/status");
            if (statusResponse.isSuccessful()) {
                String statusInfo = statusResponse.body().string();
                Log.d(TAG, "系统状态响应: " + statusInfo);
                // 简单解析获取设备ID
                if (statusInfo.contains("\"myID\":")) {
                    int start = statusInfo.indexOf("\"myID\":") + 8;
                    int end = statusInfo.indexOf("\"", start);
                    if (start > 7 && end > start) {
                        localDeviceId = statusInfo.substring(start, end);
                        Log.d(TAG, "本机设备ID: " + localDeviceId);
                    }
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "获取本机设备ID失败，继续处理: " + e.getMessage());
        }
        
        // 5. 获取本机局域网IP地址
        String[] localIPs = getLocalNetworkIPs();
        Log.d(TAG, "本机局域网IP: " + java.util.Arrays.toString(localIPs));
        
        // 6. 智能合并网络信息到设备配置中
        String enhancedDevices = enhanceDevicesWithNetworkInfo(
            devicesConfig, connectionsInfo, discoveryInfo, localDeviceId, localIPs);
        
        Log.d(TAG, "返回增强后的设备配置，设备数量: " + enhancedDevices);
        return enhancedDevices;
    }
    
    /**
     * 获取增强的设备信息（包含网络信息）
     */
    public Object getEnhancedDevices() throws IOException {
        Log.d(TAG, "开始获取增强的设备信息...");
        
        // 1. 获取设备配置
        Response configResponse = getSync("/rest/config/devices");
        if (!configResponse.isSuccessful()) {
            throw new IOException("获取设备配置失败: " + configResponse.code());
        }
        String devicesConfig = configResponse.body().string();
        Log.d(TAG, "设备配置响应: " + devicesConfig);
        
        // 2. 获取设备连接状态
        String connectionsInfo = "";
        try {
            Response connectionsResponse = getSync("/rest/system/connections");
            if (connectionsResponse.isSuccessful()) {
                connectionsInfo = connectionsResponse.body().string();
                Log.d(TAG, "设备连接状态响应: " + connectionsInfo);
            }
        } catch (Exception e) {
            Log.w(TAG, "获取设备连接状态失败，继续处理: " + e.getMessage());
        }
        
        // 3. 获取设备发现信息
        String discoveryInfo = "";
        try {
            Response discoveryResponse = getSync("/rest/system/discovery");
            if (discoveryResponse.isSuccessful()) {
                discoveryInfo = discoveryResponse.body().string();
                Log.d(TAG, "设备发现信息响应: " + discoveryInfo);
            }
        } catch (Exception e) {
            Log.w(TAG, "获取设备发现信息失败，继续处理: " + e.getMessage());
        }
        
        // 4. 获取本机设备ID
        String localDeviceId = "";
        try {
            Response statusResponse = getSync("/rest/system/status");
            if (statusResponse.isSuccessful()) {
                String statusInfo = statusResponse.body().string();
                Log.d(TAG, "系统状态响应: " + statusInfo);
                // 使用Gson解析获取设备ID
                try {
                    com.google.gson.JsonObject statusObj = new com.google.gson.Gson().fromJson(statusInfo, com.google.gson.JsonObject.class);
                    if (statusObj.has("myID")) {
                        localDeviceId = statusObj.get("myID").getAsString();
                        Log.d(TAG, "本机设备ID: " + localDeviceId);
                    } else {
                        Log.w(TAG, "系统状态响应中没有找到myID字段");
                    }
                } catch (Exception parseException) {
                    Log.w(TAG, "Gson解析系统状态失败，尝试字符串解析: " + parseException.getMessage());
                    // 回退到字符串解析
                    if (statusInfo.contains("\"myID\":")) {
                        int start = statusInfo.indexOf("\"myID\":") + 8;
                        int end = statusInfo.indexOf("\"", start);
                        if (start > 7 && end > start) {
                            localDeviceId = statusInfo.substring(start, end);
                            Log.d(TAG, "字符串解析获取本机设备ID: " + localDeviceId);
                        }
                    }
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "获取本机设备ID失败，继续处理: " + e.getMessage());
        }
        
        // 5. 获取本机局域网IP地址
        String[] localIPs = getLocalNetworkIPs();
        Log.d(TAG, "本机局域网IP: " + java.util.Arrays.toString(localIPs));
        
        // 6. 使用对象方式合并所有信息，创建增强的设备列表
        try {
            Object enhancedDevices = enhanceDevicesWithObjects(
                devicesConfig, connectionsInfo, discoveryInfo, localDeviceId, localIPs);
            Log.d(TAG, "设备增强完成，返回对象类型: " + enhancedDevices.getClass().getSimpleName());
            return enhancedDevices;
        } catch (Exception e) {
            Log.e(TAG, "设备增强失败，返回原始配置: " + e.getMessage());
            // 如果增强失败，返回原始设备配置
            try {
                com.google.gson.Gson gson = new com.google.gson.Gson();
                return gson.fromJson(devicesConfig, Object.class);
            } catch (Exception parseException) {
                Log.e(TAG, "解析原始配置也失败，返回空数组", parseException);
                return new Object[0];
            }
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
    
    /**
     * 获取本机局域网IP地址
     */
    private String[] getLocalNetworkIPs() {
        try {
            java.util.Enumeration<java.net.NetworkInterface> interfaces = java.net.NetworkInterface.getNetworkInterfaces();
            java.util.List<String> localIPs = new java.util.ArrayList<>();
            
            if (interfaces != null) {
                while (interfaces.hasMoreElements()) {
                    java.net.NetworkInterface iface = interfaces.nextElement();
                    // 跳过回环接口和down的接口
                    if (iface.isLoopback() || !iface.isUp()) {
                        continue;
                    }
                    
                    java.util.Enumeration<java.net.InetAddress> addrs = iface.getInetAddresses();
                    while (addrs.hasMoreElements()) {
                        java.net.InetAddress addr = addrs.nextElement();
                        if (addr instanceof java.net.Inet4Address && isPrivateIP(addr.getHostAddress())) {
                            localIPs.add(addr.getHostAddress());
                        }
                    }
                }
            }
            
            return localIPs.toArray(new String[0]);
        } catch (Exception e) {
            Log.e(TAG, "获取本机局域网IP失败", e);
            return new String[0];
        }
    }
    
    /**
     * 判断是否为私有IP地址
     */
    private boolean isPrivateIP(String ip) {
        try {
            String[] parts = ip.split("\\.");
            if (parts.length != 4) return false;
            
            int first = Integer.parseInt(parts[0]);
            int second = Integer.parseInt(parts[1]);
            
            // 10.0.0.0/8
            if (first == 10) return true;
            
            // 172.16.0.0/12
            if (first == 172 && second >= 16 && second <= 31) return true;
            
            // 192.168.0.0/16
            if (first == 192 && second == 168) return true;
            
            return false;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 增强设备信息，添加网络相关信息
     */
    private String enhanceDevicesWithNetworkInfo(String devicesConfig, String connectionsInfo, 
                                               String discoveryInfo, String localDeviceId, String[] localIPs) {
        try {
            // 由于设备配置是直接的数组，我们需要智能地合并网络信息
            // 从日志可以看到，设备配置格式是：[{...}, {...}]
            
            StringBuilder enhanced = new StringBuilder();
            enhanced.append("[");
            
            // 解析设备配置，为每个设备添加网络信息
            // 先去除首尾的空白字符，再检查格式
            String trimmedConfig = devicesConfig.trim();
            Log.d(TAG, "原始设备配置长度: " + devicesConfig.length());
            Log.d(TAG, "去除空白后的设备配置长度: " + trimmedConfig.length());
            Log.d(TAG, "去除空白后的设备配置首字符: '" + (trimmedConfig.length() > 0 ? trimmedConfig.charAt(0) : "空") + "'");
            Log.d(TAG, "去除空白后的设备配置末字符: '" + (trimmedConfig.length() > 0 ? trimmedConfig.charAt(trimmedConfig.length() - 1) : "空") + "'");
            
            if (trimmedConfig.startsWith("[") && trimmedConfig.endsWith("]")) {
                String devicesArray = trimmedConfig.substring(1, trimmedConfig.length() - 1);
                Log.d(TAG, "设备数组字符串: " + devicesArray);
                
                // 分割设备（简单的JSON解析）
                String[] devices = splitDevices(devicesArray);
                Log.d(TAG, "分割后的设备数量: " + devices.length);
                
                for (int i = 0; i < devices.length; i++) {
                    if (i > 0) enhanced.append(",");
                    
                    String device = devices[i];
                    String deviceId = extractDeviceId(device);
                    Log.d(TAG, "处理设备 " + i + ", ID: " + deviceId);
                    
                    // 为设备添加网络信息
                    String enhancedDevice = enhanceSingleDevice(device, deviceId, connectionsInfo, discoveryInfo, localDeviceId, localIPs);
                    enhanced.append(enhancedDevice);
                }
            } else {
                Log.w(TAG, "设备配置格式不正确，不是数组格式");
                Log.w(TAG, "期望以 [ 开头，以 ] 结尾");
                Log.w(TAG, "实际内容: " + trimmedConfig.substring(0, Math.min(100, trimmedConfig.length())));
            }
            
            enhanced.append("]");
            
            Log.d(TAG, "增强后的设备配置: " + enhanced.toString());
            return enhanced.toString();
            
        } catch (Exception e) {
            Log.e(TAG, "增强设备信息失败，返回原始配置", e);
            return devicesConfig;
        }
    }
    
    /**
     * 分割设备数组
     */
    private String[] splitDevices(String devicesArray) {
        java.util.List<String> devices = new java.util.ArrayList<>();
        int braceCount = 0;
        int start = 0;
        
        Log.d(TAG, "开始分割设备数组，长度: " + devicesArray.length());
        
        for (int i = 0; i < devicesArray.length(); i++) {
            char c = devicesArray.charAt(i);
            if (c == '{') {
                if (braceCount == 0) start = i;
                braceCount++;
                Log.d(TAG, "找到 { 在位置 " + i + ", braceCount: " + braceCount);
            } else if (c == '}') {
                braceCount--;
                Log.d(TAG, "找到 } 在位置 " + i + ", braceCount: " + braceCount);
                if (braceCount == 0) {
                    String device = devicesArray.substring(start, i + 1);
                    devices.add(device);
                    Log.d(TAG, "添加设备 " + (devices.size() - 1) + ": " + device.substring(0, Math.min(50, device.length())) + "...");
                }
            }
        }
        
        Log.d(TAG, "分割完成，找到 " + devices.size() + " 个设备");
        return devices.toArray(new String[0]);
    }
    
    /**
     * 提取设备ID
     */
    private String extractDeviceId(String device) {
        if (device.contains("\"deviceID\":")) {
            int start = device.indexOf("\"deviceID\":") + 12;
            int end = device.indexOf("\"", start);
            if (start > 11 && end > start) {
                return device.substring(start, end);
            }
        }
        return "";
    }
    
    /**
     * 增强单个设备信息
     */
    private String enhanceSingleDevice(String device, String deviceId, String connectionsInfo, 
                                     String discoveryInfo, String localDeviceId, String[] localIPs) {
        StringBuilder enhanced = new StringBuilder();
        
        // 移除最后的 } 以便添加新字段
        if (device.endsWith("}")) {
            enhanced.append(device.substring(0, device.length() - 1));
        } else {
            enhanced.append(device);
        }
        
        // 添加连接状态信息
        if (!connectionsInfo.isEmpty() && connectionsInfo.contains(deviceId)) {
            String connectionInfo = extractConnectionInfo(connectionsInfo, deviceId);
            if (!connectionInfo.isEmpty()) {
                enhanced.append(",\"connectionInfo\":").append(connectionInfo);
            }
        }
        
        // 添加发现信息
        if (!discoveryInfo.isEmpty() && discoveryInfo.contains(deviceId)) {
            String discoveryInfoForDevice = extractDiscoveryInfo(discoveryInfo, deviceId);
            if (!discoveryInfoForDevice.isEmpty()) {
                enhanced.append(",\"discoveryInfo\":").append(discoveryInfoForDevice);
            }
        }
        
        // 添加局域网地址
        java.util.List<String> lanAddresses = new java.util.ArrayList<>();
        
        // 从连接状态提取地址
        if (!connectionsInfo.isEmpty() && connectionsInfo.contains(deviceId)) {
            String address = extractAddressFromConnections(connectionsInfo, deviceId);
            if (!address.isEmpty() && isInSameNetwork(address, localIPs)) {
                lanAddresses.add(address);
                Log.d(TAG, "设备 " + deviceId + " 添加同网段连接地址: " + address);
            } else if (!address.isEmpty()) {
                Log.d(TAG, "设备 " + deviceId + " 跳过不同网段连接地址: " + address);
            }
        }
        
        // 从发现信息提取地址
        if (!discoveryInfo.isEmpty() && discoveryInfo.contains(deviceId)) {
            java.util.List<String> addresses = extractAddressesFromDiscovery(discoveryInfo, deviceId);
            for (String addr : addresses) {
                if (isInSameNetwork(addr, localIPs)) {
                    lanAddresses.add(addr);
                    Log.d(TAG, "设备 " + deviceId + " 添加同网段发现地址: " + addr);
                } else {
                    Log.d(TAG, "设备 " + deviceId + " 跳过不同网段发现地址: " + addr);
                }
            }
        }
        
        // 如果是本机设备，添加本机局域网IP
        if (deviceId.equals(localDeviceId)) {
            for (String localIP : localIPs) {
                lanAddresses.add(localIP);
            }
        }
        
        // 更新设备的地址字段
        if (!lanAddresses.isEmpty()) {
            enhanced.append(",\"lanAddresses\":[");
            for (int i = 0; i < lanAddresses.size(); i++) {
                if (i > 0) enhanced.append(",");
                enhanced.append("\"").append(lanAddresses.get(i)).append("\"");
            }
            enhanced.append("]");
        }
        
        enhanced.append("}");
        return enhanced.toString();
    }
    
    /**
     * 从连接信息中提取设备连接状态
     */
    private String extractConnectionInfo(String connectionsInfo, String deviceId) {
        try {
            if (connectionsInfo.contains("\"connections\":")) {
                int start = connectionsInfo.indexOf("\"connections\":") + 15;
                int end = connectionsInfo.lastIndexOf("}");
                if (start > 14 && end > start) {
                    String connections = connectionsInfo.substring(start, end);
                    if (connections.contains(deviceId)) {
                        int deviceStart = connections.indexOf(deviceId);
                        int deviceEnd = connections.indexOf("}", deviceStart);
                        if (deviceEnd > deviceStart) {
                            // 提取设备ID后面的内容，直到下一个设备或结束
                            String deviceContent = connections.substring(deviceStart, deviceEnd + 1);
                            // 构建正确的JSON格式，只返回设备内容部分
                            return deviceContent;
                        }
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "提取连接信息失败", e);
        }
        return "";
    }
    
    /**
     * 从发现信息中提取设备发现信息
     */
    private String extractDiscoveryInfo(String discoveryInfo, String deviceId) {
        try {
            if (discoveryInfo.contains(deviceId)) {
                int deviceStart = discoveryInfo.indexOf(deviceId);
                int deviceEnd = discoveryInfo.indexOf("}", deviceStart);
                if (deviceEnd > deviceStart) {
                    // 提取设备ID后面的内容，直到下一个设备或结束
                    String deviceContent = discoveryInfo.substring(deviceStart, deviceEnd + 1);
                    // 构建正确的JSON格式
                    return "{\"" + deviceId + "\":" + deviceContent + "}";
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "提取发现信息失败", e);
        }
        return "";
    }
    
    /**
     * 从连接信息中提取地址
     */
    private String extractAddressFromConnections(String connectionsInfo, String deviceId) {
        try {
            if (connectionsInfo.contains(deviceId)) {
                int deviceStart = connectionsInfo.indexOf(deviceId);
                if (connectionsInfo.contains("\"address\":")) {
                    int addrStart = connectionsInfo.indexOf("\"address\":", deviceStart);
                    if (addrStart > deviceStart) {
                        int start = connectionsInfo.indexOf("\"", addrStart + 10) + 1;
                        int end = connectionsInfo.indexOf("\"", start);
                        if (start > 0 && end > start) {
                            String address = connectionsInfo.substring(start, end);
                            // 提取IP地址部分
                            if (address.contains(":")) {
                                return address.substring(0, address.indexOf(":"));
                            }
                            return address;
                        }
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "提取连接地址失败", e);
        }
        return "";
    }
    
    /**
     * 从发现信息中提取地址列表
     */
    private java.util.List<String> extractAddressesFromDiscovery(String discoveryInfo, String deviceId) {
        java.util.List<String> addresses = new java.util.ArrayList<>();
        try {
            if (discoveryInfo.contains(deviceId)) {
                int deviceStart = discoveryInfo.indexOf(deviceId);
                if (discoveryInfo.contains("\"addresses\":")) {
                    int addrStart = discoveryInfo.indexOf("\"addresses\":", deviceStart);
                    if (addrStart > deviceStart) {
                        int start = discoveryInfo.indexOf("[", addrStart);
                        int end = discoveryInfo.indexOf("]", start);
                        if (start > 0 && end > start) {
                            String addressesStr = discoveryInfo.substring(start + 1, end);
                            // 分割地址
                            String[] addrArray = addressesStr.split(",");
                            for (String addr : addrArray) {
                                if (addr.contains("\"") && !addr.contains("relay://")) {
                                    String cleanAddr = addr.trim().replace("\"", "");
                                    if (cleanAddr.startsWith("tcp://") || cleanAddr.startsWith("quic://")) {
                                        String ip = cleanAddr.substring(cleanAddr.indexOf("//") + 2);
                                        if (ip.contains(":")) {
                                            ip = ip.substring(0, ip.indexOf(":"));
                                        }
                                        // 先添加到候选列表，稍后根据网段进行过滤
                                        addresses.add(ip);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "提取发现地址失败", e);
        }
        return addresses;
    }
    
    /**
     * 检查IP是否与本机在同一局域网
     */
    private boolean isInSameNetwork(String ip, String[] localIPs) {
        try {
            String[] ipParts = ip.split("\\.");
            if (ipParts.length != 4) return false;
            
            for (String localIP : localIPs) {
                String[] localParts = localIP.split("\\.");
                if (localParts.length != 4) continue;
                
                // 检查是否在同一网段
                if (isInSameSubnet(ipParts, localParts)) {
                    return true;
                }
            }
            return false;
        } catch (Exception e) {
            Log.e(TAG, "检查网段失败", e);
            return false;
        }
    }
    
    /**
     * 检查两个IP是否在同一网段
     */
    private boolean isInSameSubnet(String[] ip1, String[] localIP) {
        try {
            int first1 = Integer.parseInt(ip1[0]);
            int second1 = Integer.parseInt(ip1[1]);
            int third1 = Integer.parseInt(ip1[2]);
            
            int first2 = Integer.parseInt(localIP[0]);
            int second2 = Integer.parseInt(localIP[1]);
            int third2 = Integer.parseInt(localIP[2]);
            
            // 10.0.0.0/8 - 只检查第一个字节
            if (first1 == 10 && first2 == 10) {
                return true;
            }
            
            // 172.16.0.0/12 - 检查前两个字节
            if (first1 == 172 && first2 == 172 && 
                second1 >= 16 && second1 <= 31 && 
                second2 >= 16 && second2 <= 31) {
                return true;
            }
            
            // 192.168.0.0/16 - 检查前两个字节
            if (first1 == 192 && first2 == 192 && second1 == 168 && second2 == 168) {
                // 对于192.168.x.x，检查第三个字节是否相同
                return third1 == third2;
            }
            
            return false;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 使用对象方式增强设备信息，避免字符串拼接
     */
    private Object enhanceDevicesWithObjects(String devicesConfig, String connectionsInfo, 
                                           String discoveryInfo, String localDeviceId, String[] localIPs) {
        try {
            // 使用Gson解析JSON
            com.google.gson.Gson gson = new com.google.gson.Gson();
            
            // 1. 解析设备配置
            Device[] devices = gson.fromJson(devicesConfig, Device[].class);
            if (devices == null) {
                Log.w(TAG, "设备配置解析失败");
                return "[]";
            }
            
            Log.d(TAG, "成功解析到 " + devices.length + " 个设备");
            
            // 2. 解析连接信息
            java.util.Map<String, ConnectionInfo> connections = new java.util.HashMap<>();
            if (!connectionsInfo.isEmpty()) {
                try {
                    com.google.gson.JsonObject connectionsObj = gson.fromJson(connectionsInfo, com.google.gson.JsonObject.class);
                    if (connectionsObj.has("connections")) {
                        com.google.gson.JsonObject connectionsData = connectionsObj.getAsJsonObject("connections");
                        for (String deviceId : connectionsData.keySet()) {
                            if (!deviceId.equals("total")) {
                                try {
                                    ConnectionInfo connInfo = gson.fromJson(connectionsData.get(deviceId), ConnectionInfo.class);
                                    connections.put(deviceId, connInfo);
                                } catch (Exception e) {
                                    Log.w(TAG, "解析设备 " + deviceId + " 的连接信息失败: " + e.getMessage());
                                }
                            }
                        }
                    }
                } catch (Exception e) {
                    Log.w(TAG, "解析连接信息失败: " + e.getMessage());
                }
            }
            
            // 3. 解析发现信息
            java.util.Map<String, DiscoveryInfo> discovery = new java.util.HashMap<>();
            if (!discoveryInfo.isEmpty()) {
                try {
                    com.google.gson.JsonObject discoveryObj = gson.fromJson(discoveryInfo, com.google.gson.JsonObject.class);
                    for (String deviceId : discoveryObj.keySet()) {
                        try {
                            DiscoveryInfo discInfo = gson.fromJson(discoveryObj.get(deviceId), DiscoveryInfo.class);
                            discovery.put(deviceId, discInfo);
                        } catch (Exception e) {
                            Log.w(TAG, "解析设备 " + deviceId + " 的发现信息失败: " + e.getMessage());
                        }
                    }
                } catch (Exception e) {
                    Log.w(TAG, "解析发现信息失败: " + e.getMessage());
                }
            }
            
            // 4. 增强每个设备
            for (Device device : devices) {
                String deviceId = device.getDeviceID();
                Log.d(TAG, "处理设备: " + deviceId + " (" + device.getName() + ")");
                
                // 检查是否为本机设备
                boolean isLocalDevice = localDeviceId.equals(deviceId);
                Log.d(TAG, "设备 " + device.getName() + " ID: " + deviceId + ", 本机ID: " + localDeviceId + ", 是否本机: " + isLocalDevice);
                
                // 设置连接信息
                if (connections.containsKey(deviceId)) {
                    ConnectionInfo conn = connections.get(deviceId);
                    device.setConnected(conn.isConnected());
                    device.setConnectionType(conn.getType());
                    device.setClientVersion(conn.getClientVersion());
                    device.setInBytesTotal(conn.getInBytesTotal());
                    device.setOutBytesTotal(conn.getOutBytesTotal());
                    device.setLocalNetwork(conn.isLocal());
                    device.setCrypto(conn.getCrypto());
                } else if (isLocalDevice) {
                    // 本机设备特殊处理
                    device.setConnected(true);
                    device.setConnectionType("local");
                    device.setClientVersion("local");
                    device.setInBytesTotal(0);
                    device.setOutBytesTotal(0);
                    device.setLocalNetwork(true);
                    device.setCrypto("local");
                    Log.d(TAG, "本机设备 " + device.getName() + " 设置为在线状态");
                }
                
                // 收集地址信息
                java.util.List<String> allAddresses = new java.util.ArrayList<>();
                
                // 从连接状态获取地址
                if (connections.containsKey(deviceId)) {
                    ConnectionInfo conn = connections.get(deviceId);
                    if (conn.isConnected() && conn.getAddress() != null && !conn.getAddress().isEmpty()) {
                        String address = extractIPFromAddress(conn.getAddress());
                        if (!address.isEmpty()) {
                            allAddresses.add(address);
                        }
                    }
                    if (conn.getPrimary() != null && conn.getPrimary().getAddress() != null && 
                        !conn.getPrimary().getAddress().isEmpty()) {
                        String primaryAddress = extractIPFromAddress(conn.getPrimary().getAddress());
                        if (!primaryAddress.isEmpty() && !primaryAddress.equals(extractIPFromAddress(conn.getAddress()))) {
                            allAddresses.add(primaryAddress);
                        }
                    }
                }
                
                // 从发现信息获取地址
                if (discovery.containsKey(deviceId)) {
                    DiscoveryInfo disc = discovery.get(deviceId);
                    if (disc.getAddresses() != null) {
                        for (String addr : disc.getAddresses()) {
                            if (!addr.contains("relay://")) {
                                String ip = extractIPFromAddress(addr);
                                if (!ip.isEmpty()) {
                                    allAddresses.add(ip);
                                }
                            }
                        }
                    }
                }
                
                // 为本机设备添加本地地址
                if (isLocalDevice) {
                    for (String localIP : localIPs) {
                        allAddresses.add(localIP);
                    }
                    Log.d(TAG, "为本机设备添加本地地址: " + java.util.Arrays.toString(localIPs));
                }
                
                // 去重并过滤局域网地址
                java.util.Set<String> uniqueAddresses = new java.util.HashSet<>(allAddresses);
                java.util.List<String> lanAddresses = new java.util.ArrayList<>();
                
                for (String addr : uniqueAddresses) {
                    if (isInSameNetwork(addr, localIPs)) {
                        lanAddresses.add(addr);
                    }
                }
                
                // 设置局域网地址
                if (!lanAddresses.isEmpty()) {
                    device.setLanAddresses(lanAddresses.toArray(new String[0]));
                    Log.d(TAG, "设备 " + device.getName() + " 局域网地址: " + lanAddresses);
                }
                
                Log.d(TAG, "设备 " + device.getName() + " 更新完成，连接状态: " + device.isConnected() + 
                      ", 类型: " + device.getConnectionType() + ", 本地连接: " + device.isLocalNetwork());
            }
            
            // 5. 直接返回设备对象数组
            Log.d(TAG, "设备增强完成，共 " + devices.length + " 个设备");
            return devices;
            
        } catch (Exception e) {
            Log.e(TAG, "使用对象方式增强设备信息失败: " + e.getMessage(), e);
            // 如果对象方式失败，返回简单的设备配置，不添加网络信息
            Log.w(TAG, "回退到原始设备配置");
            try {
                com.google.gson.Gson gson = new com.google.gson.Gson();
                return gson.fromJson(devicesConfig, Object.class);
            } catch (Exception parseException) {
                Log.e(TAG, "解析原始配置也失败，返回空数组", parseException);
                return new Object[0];
            }
        }
    }
    
    /**
     * 从地址字符串中提取IP地址
     */
    private String extractIPFromAddress(String address) {
        if (address == null || address.isEmpty()) {
            return "";
        }
        
        // 匹配IPv4地址的正则表达式
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})");
        java.util.regex.Matcher matcher = pattern.matcher(address);
        
        if (matcher.find()) {
            return matcher.group(1);
        }
        
        return "";
    }
}
