package com.nutomic.syncthingandroid.fragments;

import android.os.Bundle;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import com.nutomic.syncthingandroid.R;
import com.nutomic.syncthingandroid.model.Device;
import com.nutomic.syncthingandroid.service.RestApi;
import com.nutomic.syncthingandroid.activities.SyncthingActivity;

public class DeviceFragment extends Fragment {
    private static final String ARG_DEVICE_ID = "device_id";
    private String mDeviceId;
    private Device mDevice;

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
        SyncthingActivity activity = (SyncthingActivity) getActivity();
        RestApi api = activity.getApi();
        if (api != null) {
            for (Device d : api.getDevices(true)) {
                if (d.deviceID.equals(mDeviceId)) {
                    mDevice = d;
                    break;
                }
            }
        }
        if (mDevice != null) {
            textView.setText(getString(R.string.device_id) + ": " + mDevice.deviceID + "\n" +
                    getString(R.string.device_name) + ": " + mDevice.getDisplayName());
        } else {
            textView.setText(R.string.device_state_unknown);
        }
        return view;
    }
} 