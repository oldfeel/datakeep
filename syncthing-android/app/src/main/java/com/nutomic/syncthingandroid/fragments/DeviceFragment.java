package com.nutomic.syncthingandroid.fragments;

import android.os.Bundle;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import android.widget.ImageView;
import android.widget.LinearLayout;
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
    private TextView mDeviceIdView;
    private TextView mDeviceIpView;
    private ImageView mToggleButton;
    private LinearLayout mDeviceInfoContainer;
    private boolean mIsExpanded = false;

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
        
        // 绑定UI组件
        mDeviceIdView = view.findViewById(R.id.device_id);
        mDeviceIpView = view.findViewById(R.id.device_ip);
        mToggleButton = view.findViewById(R.id.toggle_button);
        mDeviceInfoContainer = view.findViewById(R.id.device_info_container);
        
        // 设置展开/收起按钮点击事件
        mToggleButton.setOnClickListener(v -> toggleExpanded());
        
        // 初始加载设备信息
        updateDeviceInfo();
        
        return view;
    }
    
    private void toggleExpanded() {
        mIsExpanded = !mIsExpanded;
        
        if (mIsExpanded) {
            mDeviceInfoContainer.setVisibility(View.VISIBLE);
            mToggleButton.setImageResource(android.R.drawable.arrow_up_float);
            // 展开时移除单行限制，允许换行显示完整内容
            mDeviceIdView.setSingleLine(false);
            mDeviceIdView.setEllipsize(null);
        } else {
            mDeviceInfoContainer.setVisibility(View.GONE);
            mToggleButton.setImageResource(android.R.drawable.arrow_down_float);
            // 收起时恢复单行限制，用省略号结尾
            mDeviceIdView.setSingleLine(true);
            mDeviceIdView.setEllipsize(android.text.TextUtils.TruncateAt.END);
        }
    }
    
    private void updateDeviceInfo() {
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
                                    mDeviceIdView.setText("API 错误: " + errorMsg);
                                    mDeviceIpView.setText("");
                                });
                                return;
                            }
                            devices = jsonResponse.getJSONArray("data");
                        } else if (jsonResponse.has("devices")) {
                            devices = jsonResponse.getJSONArray("devices");
                        } else {
                            Log.e(TAG, "未知的响应格式: " + responseBody);
                            requireActivity().runOnUiThread(() -> {
                                mDeviceIdView.setText("未知的响应格式");
                                mDeviceIpView.setText("");
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
                                    // 设置设备ID
                                    mDeviceIdView.setText(mDevice.deviceID);
                                    
                                    // 设置IP地址
                                    if (mDevice.addresses != null && !mDevice.addresses.isEmpty()) {
                                        StringBuilder ipBuilder = new StringBuilder();
                                        for (int k = 0; k < mDevice.addresses.size(); k++) {
                                            if (k > 0) ipBuilder.append(", ");
                                            ipBuilder.append(mDevice.addresses.get(k));
                                        }
                                        mDeviceIpView.setText(ipBuilder.toString());
                                    } else {
                                        mDeviceIpView.setText("无可用地址");
                                    }
                                });
                                return;
                            }
                        }
                        
                        // 如果没找到设备
                        requireActivity().runOnUiThread(() -> {
                            mDeviceIdView.setText("未找到设备信息");
                            mDeviceIpView.setText("");
                        });
                        
                    } catch (Exception e) {
                        Log.e(TAG, "解析设备信息失败", e);
                        requireActivity().runOnUiThread(() -> {
                            mDeviceIdView.setText("解析设备信息失败: " + e.getMessage());
                            mDeviceIpView.setText("");
                        });
                    }
                } else {
                    Log.e(TAG, "HTTP 请求失败: " + response.code());
                    requireActivity().runOnUiThread(() -> {
                        mDeviceIdView.setText("HTTP 请求失败: " + response.code());
                        mDeviceIpView.setText("");
                    });
                }
            }
            
            @Override
            public void onFailure(okhttp3.Call call, IOException e) {
                Log.e(TAG, "获取设备信息失败: " + e.getMessage());
                requireActivity().runOnUiThread(() -> {
                    mDeviceIdView.setText("获取设备信息失败: " + e.getMessage());
                    mDeviceIpView.setText("");
                });
            }
        });
    }
} 