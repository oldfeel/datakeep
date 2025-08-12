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
            String response = mHttpClient.getDevices();
            Log.i(TAG, "设备列表获取成功");
            
            // 包装响应格式，添加 success 和 data 字段
            String wrappedResponse = "{\"success\":true,\"data\":" + response + "}";
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取设备列表失败", e);
            promise.reject("API_ERROR", "获取设备列表失败: " + e.getMessage(), e);
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
            
            // 包装响应格式，添加 success 和 data 字段
            String wrappedResponse = "{\"success\":true,\"data\":" + response + "}";
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取设备文件夹失败", e);
            promise.reject("API_ERROR", "获取设备文件夹失败: " + e.getMessage(), e);
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
            
            // 包装响应格式，添加 success 和 data 字段
            String wrappedResponse = "{\"success\":true,\"data\":" + response + "}";
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取文件夹文件失败", e);
            promise.reject("API_ERROR", "获取文件夹文件失败: " + e.getMessage(), e);
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
            
            // 包装响应格式，添加 success 和 data 字段
            String wrappedResponse = "{\"success\":true,\"data\":" + response + "}";
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取本机设备ID失败", e);
            promise.reject("API_ERROR", "获取本机设备ID失败: " + e.getMessage(), e);
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
            
            // 包装响应格式，添加 success 和 data 字段
            String wrappedResponse = "{\"success\":true,\"data\":" + response + "}";
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取WiFi信息失败", e);
            promise.reject("API_ERROR", "获取WiFi信息失败: " + e.getMessage(), e);
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
            
            // 包装响应格式，添加 success 和 data 字段
            String wrappedResponse = "{\"success\":true,\"data\":" + response + "}";
            Log.d(TAG, "包装后的响应: " + wrappedResponse);
            
            promise.resolve(wrappedResponse);
        } catch (Exception e) {
            Log.e(TAG, "获取附近设备失败", e);
            promise.reject("API_ERROR", "获取附近设备失败: " + e.getMessage(), e);
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
            
            // 如果响应为空，创建一个成功的响应
            if (response == null || response.trim().isEmpty()) {
                response = "{\"success\":true,\"data\":{\"status\":\"added\"}}";
                Log.d(TAG, "响应为空，创建默认成功响应: " + response);
            } else {
                // 包装响应格式，添加 success 和 data 字段
                response = "{\"success\":true,\"data\":" + response + "}";
                Log.d(TAG, "包装后的响应: " + response);
            }
            
            promise.resolve(response);
        } catch (Exception e) {
            Log.e(TAG, "添加设备失败", e);
            promise.reject("API_ERROR", "添加设备失败: " + e.getMessage(), e);
        }
    }
} 