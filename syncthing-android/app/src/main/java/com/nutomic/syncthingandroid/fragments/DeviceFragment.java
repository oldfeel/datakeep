package com.nutomic.syncthingandroid.fragments;

import android.os.Bundle;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import android.widget.Button;
import android.util.Log;
import com.nutomic.syncthingandroid.R;
import com.nutomic.syncthingandroid.model.Device;
import com.nutomic.syncthingandroid.service.RestApi;
import com.nutomic.syncthingandroid.activities.SyncthingActivity;
import com.nutomic.syncthingandroid.util.HttpClient;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.IOException;
import java.util.ArrayList;

public class DeviceFragment extends Fragment {
    private static final String TAG = "DeviceFragment";
    private static final String ARG_DEVICE_ID = "device_id";
    private String mDeviceId;
    private Device mDevice;
    private HttpClient mHttpClient;

    public static DeviceFragment newInstance(String deviceId) {
        DeviceFragment fragment = new DeviceFragment();
        Bundle args = new Bundle();
        args.putString(ARG_DEVICE_ID, deviceId);
        fragment.setArguments(args);
        return fragment;
    }

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (getArguments() != null) {
            mDeviceId = getArguments().getString(ARG_DEVICE_ID);
        }
    }

    @Nullable
    @Override
    public View onCreateView(LayoutInflater inflater, @Nullable ViewGroup container, @Nullable Bundle savedInstanceState) {
        View view = inflater.inflate(R.layout.fragment_device, container, false);
        TextView textView = view.findViewById(R.id.device_info);
        Button refreshButton = view.findViewById(R.id.refresh_button);
        
        // 设置刷新按钮点击事件
        refreshButton.setOnClickListener(v -> updateDeviceInfo(textView));
        
        // 初始加载设备信息
        updateDeviceInfo(textView);
        
        return view;
    }
    
    private void updateDeviceInfo(TextView textView) {
        // 使用 HTTP API 获取设备信息
        if (mHttpClient == null) {
            mHttpClient = new HttpClient();
        }
        
        mHttpClient.getDevices(new okhttp3.Callback() {
            @Override
            public void onResponse(okhttp3.Call call, okhttp3.Response response) throws IOException {
                if (response.isSuccessful()) {
                    String responseBody = response.body().string();
                    
                    try {
                        JSONObject jsonResponse = new JSONObject(responseBody);
                        JSONArray devices;
                        
                        // 检查响应格式
                        if (jsonResponse.has("code") && jsonResponse.has("data")) {
                            int code = jsonResponse.getInt("code");
                            if (code != 0) {
                                String errorMsg = jsonResponse.optString("data", "未知错误");
                                Log.e(TAG, "API 返回错误: code=" + code + ", message=" + errorMsg);
                                requireActivity().runOnUiThread(() -> {
                                    textView.setText("API 错误: " + errorMsg);
                                });
                                return;
                            }
                            devices = jsonResponse.getJSONArray("data");
                        } else if (jsonResponse.has("devices")) {
                            devices = jsonResponse.getJSONArray("devices");
                        } else {
                            Log.e(TAG, "未知的响应格式: " + responseBody);
                            requireActivity().runOnUiThread(() -> {
                                textView.setText("未知的响应格式");
                            });
                            return;
                        }
                        
                        // 查找当前设备
                        for (int i = 0; i < devices.length(); i++) {
                            JSONObject deviceJson = devices.getJSONObject(i);
                            String deviceID = deviceJson.getString("deviceID");
                            
                            if (deviceID.equals(mDeviceId)) {
                                // 解析设备信息
                                mDevice = new Device();
                                mDevice.deviceID = deviceID;
                                mDevice.name = deviceJson.optString("name", "未知设备");
                                mDevice.addresses = new ArrayList<>();
                                
                                // 解析地址数组
                                if (deviceJson.has("addresses")) {
                                    JSONArray addresses = deviceJson.getJSONArray("addresses");
                                    for (int j = 0; j < addresses.length(); j++) {
                                        mDevice.addresses.add(addresses.getString(j));
                                    }
                                }
                                
                                // 解析其他字段
                                mDevice.compression = deviceJson.optString("compression", "");
                                mDevice.certName = deviceJson.optString("certName", "");
                                mDevice.introducer = deviceJson.optBoolean("introducer", false);
                                mDevice.paused = !deviceJson.optBoolean("connected", false);
                                
                                // 在主线程更新 UI
                                requireActivity().runOnUiThread(() -> {
                                    StringBuilder deviceInfo = new StringBuilder();
                                    deviceInfo.append("📱 设备信息\n");
                                    deviceInfo.append("═══════════\n\n");
                                    
                                    // 设备基本信息
                                    deviceInfo.append("📛 设备名称: ").append(mDevice.getDisplayName()).append("\n");
                                    deviceInfo.append("🆔 设备ID: ").append(mDevice.deviceID).append("\n\n");
                                    
                                    // 显示 IP 地址信息
                                    deviceInfo.append("🌐 网络地址:\n");
                                    if (mDevice.addresses != null && !mDevice.addresses.isEmpty()) {
                                        for (int k = 0; k < mDevice.addresses.size(); k++) {
                                            deviceInfo.append("   ").append(k + 1).append(". ").append(mDevice.addresses.get(k)).append("\n");
                                        }
                                    } else {
                                        deviceInfo.append("   无可用地址\n");
                                    }
                                    deviceInfo.append("\n");
                                    
                                    // 其他设备信息
                                    deviceInfo.append("⚙️ 设备配置:\n");
                                    if (mDevice.compression != null && !mDevice.compression.isEmpty()) {
                                        deviceInfo.append("   压缩: ").append(mDevice.compression).append("\n");
                                    }
                                    
                                    if (mDevice.certName != null && !mDevice.certName.isEmpty()) {
                                        deviceInfo.append("   证书: ").append(mDevice.certName).append("\n");
                                    }
                                    
                                    deviceInfo.append("   介绍者: ").append(mDevice.introducer ? "是" : "否").append("\n");
                                    deviceInfo.append("   状态: ").append(mDevice.paused ? "⏸️ 已暂停" : "▶️ 运行中").append("\n");
                                    
                                    // 显示连接信息
                                    boolean connected = deviceJson.optBoolean("connected", false);
                                    String connectionType = deviceJson.optString("connectionType", "");
                                    String clientVersion = deviceJson.optString("clientVersion", "");
                                    boolean isLocalNetwork = deviceJson.optBoolean("isLocalNetwork", false);
                                    String crypto = deviceJson.optString("crypto", "");
                                    
                                    deviceInfo.append("\n🔗 连接信息:\n");
                                    deviceInfo.append("   连接状态: ").append(connected ? "🟢 已连接" : "🔴 未连接").append("\n");
                                    if (!connectionType.isEmpty()) {
                                        deviceInfo.append("   连接类型: ").append(connectionType).append("\n");
                                    }
                                    if (!clientVersion.isEmpty()) {
                                        deviceInfo.append("   客户端版本: ").append(clientVersion).append("\n");
                                    }
                                    deviceInfo.append("   本地网络: ").append(isLocalNetwork ? "是" : "否").append("\n");
                                    if (!crypto.isEmpty()) {
                                        deviceInfo.append("   加密: ").append(crypto).append("\n");
                                    }
                                    
                                    textView.setText(deviceInfo.toString());
                                });
                                return;
                            }
                        }
                        
                        // 如果没找到设备
                        requireActivity().runOnUiThread(() -> {
                            textView.setText("未找到设备信息");
                        });
                        
                    } catch (Exception e) {
                        Log.e(TAG, "解析设备信息失败", e);
                        requireActivity().runOnUiThread(() -> {
                            textView.setText("解析设备信息失败: " + e.getMessage());
                        });
                    }
                } else {
                    Log.e(TAG, "HTTP 请求失败: " + response.code());
                    requireActivity().runOnUiThread(() -> {
                        textView.setText("HTTP 请求失败: " + response.code());
                    });
                }
            }
            
            @Override
            public void onFailure(okhttp3.Call call, IOException e) {
                Log.e(TAG, "获取设备信息失败: " + e.getMessage());
                requireActivity().runOnUiThread(() -> {
                    textView.setText("获取设备信息失败: " + e.getMessage());
                });
            }
        });
    }
} 