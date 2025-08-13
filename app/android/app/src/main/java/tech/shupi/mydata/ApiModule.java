package tech.shupi.mydata;

import android.util.Log;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.Arguments;

import tech.shupi.mydata.util.HttpClient;

/**
 * React Native Native Module for API access
 */
public class ApiModule extends ReactContextBaseJavaModule {
    private static final String TAG = "ApiModule";
    private final HttpClient mHttpClient;
    
    public ApiModule(ReactApplicationContext reactContext) {
        super(reactContext);
        mHttpClient = new HttpClient();
        Log.i(TAG, "ApiModule 初始化完成");
    }
    
    @Override
    public String getName() {
        return "ApiModule";
    }
    
    /**
     * 获取设备列表
     */
    @ReactMethod
    public void getDevices(Promise promise) {
        try {
            Log.d(TAG, "开始获取设备列表...");
            // 直接使用增强的设备信息，包含网络连接状态
            Object devices = mHttpClient.getEnhancedDevices();
            Log.i(TAG, "设备列表获取成功");
            
            // 直接使用对象，不需要字符串转换
            String wrappedResponse = success(devices);
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取设备列表失败", e);
            String errorResponse = fail(500, "获取设备列表失败: " + e.getMessage());
            promise.resolve(errorResponse);
        }
    }
    
    /**
     * 获取增强的设备信息（包含网络信息）
     */
    @ReactMethod
    public void getEnhancedDevices(Promise promise) {
        try {
            Log.d(TAG, "开始获取增强的设备信息...");
            Object devices = mHttpClient.getEnhancedDevices();
            Log.i(TAG, "增强设备信息获取成功");
            
            // 直接使用对象，不需要字符串转换
            String wrappedResponse = success(devices);
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取增强设备信息失败", e);
            String errorResponse = fail(500, "获取增强设备信息失败: " + e.getMessage());
            promise.resolve(errorResponse);
        }
    }
    
    /**
     * 获取设备文件夹
     */
    @ReactMethod
    public void getDeviceFolders(String deviceId, Promise promise) {
        try {
            Log.d(TAG, "开始获取设备文件夹: " + deviceId);
            String response = mHttpClient.getDeviceFolders(deviceId);
            Log.i(TAG, "设备文件夹获取成功");
            
            // 使用与Go后端一致的响应格式
            String wrappedResponse = success(response);
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取设备文件夹失败", e);
            String errorResponse = fail(500, "获取设备文件夹失败: " + e.getMessage());
            promise.resolve(errorResponse);
        }
    }
    
    /**
     * 获取文件夹文件
     */
    @ReactMethod
    public void getFolderFiles(String folderId, Promise promise) {
        try {
            Log.d(TAG, "开始获取文件夹文件: " + folderId);
            String response = mHttpClient.getFolderFiles(folderId);
            Log.i(TAG, "文件夹文件获取成功");
            
            // 使用与Go后端一致的响应格式
            String wrappedResponse = success(response);
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取文件夹文件失败", e);
            String errorResponse = fail(500, "获取文件夹文件失败: " + e.getMessage());
            promise.resolve(errorResponse);
        }
    }
    
    /**
     * 获取本机设备ID
     */
    @ReactMethod
    public void getLocalDeviceId(Promise promise) {
        try {
            Log.d(TAG, "开始获取本机设备ID...");
            String response = mHttpClient.getLocalDeviceId();
            Log.i(TAG, "本机设备ID获取成功");
            
            // 使用与Go后端一致的响应格式
            String wrappedResponse = success(response);
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取本机设备ID失败", e);
            String errorResponse = fail(500, "获取本机设备ID失败: " + e.getMessage());
            promise.resolve(errorResponse);
        }
    }
    
    /**
     * 获取WiFi信息
     */
    @ReactMethod
    public void getWifiInfo(Promise promise) {
        try {
            Log.d(TAG, "开始获取WiFi信息...");
            String response = mHttpClient.getWifiInfo();
            Log.i(TAG, "WiFi信息获取成功");
            
            // 使用与Go后端一致的响应格式
            String wrappedResponse = success(response);
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取WiFi信息失败", e);
            String errorResponse = fail(500, "获取WiFi信息失败: " + e.getMessage());
            promise.resolve(errorResponse);
        }
    }
    
    /**
     * 获取附近发现的设备
     */
    @ReactMethod
    public void getNearbyDevices(Promise promise) {
        try {
            Log.d(TAG, "开始获取附近设备...");
            String response = mHttpClient.getNearbyDevices();
            Log.i(TAG, "附近设备获取成功");
            
            // 使用与Go后端一致的响应格式
            String wrappedResponse = success(response);
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取附近设备失败", e);
            String errorResponse = fail(500, "获取附近设备失败: " + e.getMessage());
            promise.resolve(errorResponse);
        }
    }
    
    /**
     * 添加设备
     */
    @ReactMethod
    public void addDevice(String deviceConfig, Promise promise) {
        try {
            Log.d(TAG, "开始添加设备...");
            String response = mHttpClient.addDevice(deviceConfig);
            Log.i(TAG, "设备添加成功");
            
            if (response == null || response.trim().isEmpty()) {
                // 如果响应为空，创建一个默认的成功状态
                com.google.gson.JsonObject defaultData = new com.google.gson.JsonObject();
                defaultData.addProperty("status", "added");
                String wrappedResponse = success(defaultData.toString());
                Log.d(TAG, "响应为空，创建默认成功响应");
                promise.resolve(wrappedResponse);
            } else {
                // 使用与Go后端一致的响应格式
                String wrappedResponse = success(response);
                Log.d(TAG, "包装现有响应");
                promise.resolve(wrappedResponse);
            }
        } catch (Exception e) {
            Log.e(TAG, "添加设备失败", e);
            String errorResponse = fail(500, "添加设备失败: " + e.getMessage());
            promise.resolve(errorResponse);
        }
    }
    
    /**
     * 构建成功响应，与Go后端格式一致
     */
    private String success(Object data) {
        try {
            com.google.gson.JsonObject jsonResponse = new com.google.gson.JsonObject();
            jsonResponse.addProperty("code", 0);
            
            // 直接使用 Gson 将对象转换为 JsonElement
            com.google.gson.Gson gson = new com.google.gson.Gson();
            com.google.gson.JsonElement dataElement = gson.toJsonTree(data);
            jsonResponse.add("data", dataElement);
            
            return jsonResponse.toString();
        } catch (Exception e) {
            Log.e(TAG, "构建成功响应失败", e);
            // 如果失败，返回错误响应
            com.google.gson.JsonObject jsonResponse = new com.google.gson.JsonObject();
            jsonResponse.addProperty("code", 500);
            jsonResponse.addProperty("data", "内部错误");
            return jsonResponse.toString();
        }
    }
    
    /**
     * 构建失败响应，与Go后端格式一致
     */
    private String fail(int code, String message) {
        com.google.gson.JsonObject jsonResponse = new com.google.gson.JsonObject();
        jsonResponse.addProperty("code", code);
        jsonResponse.addProperty("data", message);
        return jsonResponse.toString();
    }
} 