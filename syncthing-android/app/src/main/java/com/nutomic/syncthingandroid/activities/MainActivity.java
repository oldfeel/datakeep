package com.nutomic.syncthingandroid.activities;

import android.annotation.SuppressLint;
import android.app.Activity;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import android.app.Dialog;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.drawable.BitmapDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.PersistableBundle;
import android.os.PowerManager;
import android.provider.Settings;

import com.google.android.material.color.DynamicColors;
import com.google.android.material.tabs.TabLayout;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentManager;
import androidx.fragment.app.FragmentPagerAdapter;
import androidx.core.view.GravityCompat;
import androidx.viewpager.widget.ViewPager;
import androidx.drawerlayout.widget.DrawerLayout;
import androidx.appcompat.app.ActionBar;
import androidx.appcompat.app.ActionBarDrawerToggle;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuInflater;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import android.widget.LinearLayout;
import android.widget.Button;
import android.widget.ImageButton;

import com.annimon.stream.function.Consumer;
import com.nutomic.syncthingandroid.R;
import com.nutomic.syncthingandroid.SyncthingApp;
import com.nutomic.syncthingandroid.fragments.DeviceListFragment;
import com.nutomic.syncthingandroid.fragments.DrawerFragment;
import com.nutomic.syncthingandroid.fragments.FolderListFragment;
import com.nutomic.syncthingandroid.fragments.DeviceFragment;
import com.nutomic.syncthingandroid.model.Device;
import com.nutomic.syncthingandroid.service.Constants;
import com.nutomic.syncthingandroid.service.RestApi;
import com.nutomic.syncthingandroid.service.SyncthingService;
import com.nutomic.syncthingandroid.service.SyncthingServiceBinder;
import com.nutomic.syncthingandroid.util.HttpClient;
import com.nutomic.syncthingandroid.util.PermissionUtil;
import com.nutomic.syncthingandroid.util.Util;
import java.util.Date;
import java.util.concurrent.TimeUnit;
import java.util.ArrayList;
import java.util.List;
import java.io.IOException;
import org.json.JSONArray;
import org.json.JSONObject;

import javax.inject.Inject;

import static java.lang.Math.min;

/**
 * Shows {@link FolderListFragment} and
 * {@link DeviceListFragment} in different tabs, and
 * {@link DrawerFragment} in the navigation drawer.
 */
public class MainActivity extends StateDialogActivity
        implements SyncthingService.OnServiceStateChangeListener {

    private static final String TAG = "MainActivity";
    private static final String IS_SHOWING_RESTART_DIALOG = "RESTART_DIALOG_STATE";
    private static final String BATTERY_DIALOG_DISMISSED = "BATTERY_DIALOG_STATE";
    private static final String IS_QRCODE_DIALOG_DISPLAYED = "QRCODE_DIALOG_STATE";
    private static final String QRCODE_BITMAP_KEY = "QRCODE_BITMAP";
    private static final String DEVICEID_KEY = "DEVICEID";

    /**
     * Time after first start when usage reporting dialog should be shown.
     *
     * @see #showUsageReportingDialog()
     */
    private static final long USAGE_REPORTING_DIALOG_DELAY = TimeUnit.DAYS.toMillis(3);

    private AlertDialog mBatteryOptimizationsDialog;
    private AlertDialog mQrCodeDialog;
    private Dialog mRestartDialog;

    private boolean mBatteryOptimizationDialogDismissed;

    private ViewPager mViewPager;

    private FolderListFragment mFolderListFragment;
    private DeviceListFragment mDeviceListFragment;
    private DrawerFragment     mDrawerFragment;

    private ActionBarDrawerToggle mDrawerToggle;
    private DrawerLayout          mDrawerLayout;
    @Inject SharedPreferences mPreferences;

    private List<Fragment> mFragments = new ArrayList<>();
    private List<String> mFragmentTitles = new ArrayList<>();
    private FragmentPagerAdapter mDynamicPagerAdapter;

    private LinearLayout mTabButtonContainer;
    private int mCurrentTabIndex = 0;
    private HttpClient mHttpClient;

    /**
     * Handles various dialogs based on current state.
     */
    @Override
    public void onServiceStateChange(SyncthingService.State currentState) {
        switch (currentState) {
            case STARTING:
                break;
            case ACTIVE:
                getIntent().putExtra(this.EXTRA_KEY_GENERATION_IN_PROGRESS, false);
                showBatteryOptimizationDialogIfNecessary();
                mDrawerLayout.setDrawerLockMode(DrawerLayout.LOCK_MODE_UNLOCKED);
                mDrawerFragment.requestGuiUpdate();
                setupTabs();
                Boolean usageReportingDelayPassed = (new Date().getTime() > getFirstStartTime() + USAGE_REPORTING_DIALOG_DELAY);
                RestApi restApi = getApi();
                if (usageReportingDelayPassed && restApi != null && !restApi.isUsageReportingDecided()) {
                    showUsageReportingDialog(restApi);
                }
                break;
            case ERROR:
                finish();
                break;
            case DISABLED:
                break;
        }
    }

    private void showBatteryOptimizationDialogIfNecessary() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M)
            return;
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        boolean dontShowAgain = mPreferences.getBoolean("battery_optimization_dont_show_again", false);
        if (dontShowAgain || mBatteryOptimizationsDialog != null ||
                pm.isIgnoringBatteryOptimizations(getPackageName()) ||
                mBatteryOptimizationDialogDismissed) {
            return;
        }

        mBatteryOptimizationsDialog = Util.getAlertDialogBuilder(this)
                .setTitle(R.string.dialog_disable_battery_optimization_title)
                .setMessage(R.string.dialog_disable_battery_optimization_message)
                .setPositiveButton(R.string.dialog_disable_battery_optimization_turn_off, (d, i) -> {
                    Intent intent = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
                    intent.setData(Uri.parse("package:" + getPackageName()));
                    try {
                        startActivity(intent);
                    } catch (ActivityNotFoundException e) {
                        // Some devices dont seem to support this request (according to Google Play
                        // crash reports).
                        Log.w(TAG, "Request ignore battery optimizations not supported", e);
                        Toast.makeText(this, R.string.dialog_disable_battery_optimizations_not_supported, Toast.LENGTH_LONG).show();
                        mPreferences.edit().putBoolean("battery_optimization_dont_show_again", true).apply();
                    }
                })
                .setNeutralButton(R.string.dialog_disable_battery_optimization_later, (d, i) -> mBatteryOptimizationDialogDismissed = true)
                .setNegativeButton(R.string.dialog_disable_battery_optimization_dont_show_again, (d, i) ->
                        mPreferences.edit().putBoolean("battery_optimization_dont_show_again", true).apply())
                .setOnCancelListener(d -> mBatteryOptimizationDialogDismissed = true)
                .show();
    }

    /**
     * Returns the unix timestamp at which the app was first installed.
     */
    private long getFirstStartTime() {
        PackageManager pm = getPackageManager();
        long firstInstallTime = 0;
        try {
            firstInstallTime = pm.getPackageInfo(getPackageName(), 0).firstInstallTime;
        } catch (PackageManager.NameNotFoundException e) {
            Log.w(TAG, "This should never happen", e);
        }
        return firstInstallTime;
    }

    private void setupTabs() {
        mFragments.clear();
        mFragmentTitles.clear();
        // 本机文件tab
        mFragments.add(mFolderListFragment);
        mFragmentTitles.add(getString(R.string.local_files_tab));
        
        // 从 HTTP API 获取设备列表并动态添加设备tab
        loadDevicesFromHttpApi();
    }
    
    private void loadDevicesFromHttpApi() {
        Log.d(TAG, "从 HTTP API 加载设备列表");
        
        if (mHttpClient == null) {
            mHttpClient = new HttpClient();
        }
        
        mHttpClient.getDevices(new okhttp3.Callback() {
            @Override
            public void onResponse(okhttp3.Call call, okhttp3.Response response) throws IOException {
                if (response.isSuccessful()) {
                    String responseBody = response.body().string();
                    
                    // 打印原始响应数据
                    Log.d(TAG, "设备列表接口返回数据:");
                    Log.d(TAG, "状态码: " + response.code());
                    Log.d(TAG, "响应头: " + response.headers());
                    Log.d(TAG, "响应体: " + responseBody);
                    
                    try {
                        JSONObject jsonResponse = new JSONObject(responseBody);
                        JSONArray devices = jsonResponse.getJSONArray("devices");
                        
                        Log.d(TAG, "解析到 " + devices.length() + " 个设备");
                        
                        List<Device> deviceList = new ArrayList<>();
                        for (int i = 0; i < devices.length(); i++) {
                            JSONObject deviceJson = devices.getJSONObject(i);
                            Device device = new Device();
                            device.deviceID = deviceJson.getString("deviceID");
                            device.name = deviceJson.optString("name", "未知设备");
                            device.addresses = new ArrayList<>(); // 初始化为空列表
                            
                            // 解析地址数组
                            if (deviceJson.has("addresses")) {
                                JSONArray addresses = deviceJson.getJSONArray("addresses");
                                for (int j = 0; j < addresses.length(); j++) {
                                    device.addresses.add(addresses.getString(j));
                                }
                            }
                            
                            // 打印每个设备的详细信息
                            Log.d(TAG, "设备 " + (i + 1) + ":");
                            Log.d(TAG, "  - deviceID: " + device.deviceID);
                            Log.d(TAG, "  - name: " + device.name);
                            Log.d(TAG, "  - addresses: " + device.addresses);
                            
                            deviceList.add(device);
                        }
                        
                        // 在主线程更新 UI
                        runOnUiThread(() -> {
                            // 添加设备tab
                            for (Device device : deviceList) {
                                mFragments.add(DeviceFragment.newInstance(device.deviceID));
                                mFragmentTitles.add(device.getDisplayName());
                            }
                            
                            // 更新适配器
                            mDynamicPagerAdapter = new FragmentPagerAdapter(getSupportFragmentManager()) {
                                @Override
                                public Fragment getItem(int position) { return mFragments.get(position); }
                                @Override
                                public int getCount() { return mFragments.size(); }
                                @Override
                                public CharSequence getPageTitle(int position) { return mFragmentTitles.get(position); }
                            };
                            mViewPager.setAdapter(mDynamicPagerAdapter);
                            
                            // 设置按钮导航栏
                            setupTabButtons();
                            
                            Log.d(TAG, "设备列表加载完成，共 " + deviceList.size() + " 个设备");
                        });
                        
                    } catch (Exception e) {
                        Log.e(TAG, "解析设备列表失败", e);
                        runOnUiThread(() -> {
                            Toast.makeText(MainActivity.this, 
                                "解析设备列表失败: " + e.getMessage(), 
                                Toast.LENGTH_SHORT).show();
                        });
                    }
                } else {
                    Log.e(TAG, "HTTP 请求失败: " + response.code());
                    String errorBody = response.body() != null ? response.body().string() : "无错误详情";
                    Log.e(TAG, "错误响应: " + errorBody);
                    runOnUiThread(() -> {
                        Toast.makeText(MainActivity.this, 
                            "HTTP 请求失败: " + response.code(), 
                            Toast.LENGTH_SHORT).show();
                    });
                }
            }
            
            @Override
            public void onFailure(okhttp3.Call call, IOException e) {
                Log.e(TAG, "加载设备列表失败: " + e.getMessage());
                runOnUiThread(() -> {
                    Toast.makeText(MainActivity.this, 
                        "加载设备列表失败: " + e.getMessage(), 
                        Toast.LENGTH_SHORT).show();
                });
            }
        });
    }

    private void setupTabButtons() {
        if (mTabButtonContainer == null) {
            mTabButtonContainer = findViewById(R.id.tabButtonContainer);
        }
        mTabButtonContainer.removeAllViews();
        // 本机文件按钮
        addTabButton(getString(R.string.local_files_tab), 0);
        // 设备按钮
        for (int i = 1; i < mFragmentTitles.size(); i++) {
            addTabButton(mFragmentTitles.get(i), i);
        }
        // 添加"+"按钮
        ImageButton addBtn = new ImageButton(this);
        addBtn.setImageResource(android.R.drawable.ic_menu_add);
        addBtn.setContentDescription(getString(R.string.add_device));
        addBtn.setBackgroundResource(android.R.color.transparent);
        addBtn.setPadding(32, 8, 32, 8);
        addBtn.setOnClickListener(v -> {
            Intent intent = new Intent(this, com.nutomic.syncthingandroid.activities.DeviceActivity.class)
                    .putExtra(com.nutomic.syncthingandroid.activities.DeviceActivity.EXTRA_IS_CREATE, true);
            startActivity(intent);
        });
        mTabButtonContainer.addView(addBtn);
    }

    private void addTabButton(String title, int index) {
        Button btn = new Button(this);
        btn.setText(title);
        btn.setAllCaps(false);
        btn.setBackgroundResource(android.R.color.transparent);
        btn.setPadding(32, 8, 32, 8);
        btn.setTextColor(getResources().getColor(android.R.color.black));
        btn.setOnClickListener(v -> {
            mViewPager.setCurrentItem(index, true);
            highlightTabButton(index);
        });
        mTabButtonContainer.addView(btn);
        // 默认高亮第一个
        if (index == mCurrentTabIndex) {
            btn.setAlpha(1f);
        } else {
            btn.setAlpha(0.6f);
        }
    }

    private void highlightTabButton(int index) {
        mCurrentTabIndex = index;
        for (int i = 0; i < mTabButtonContainer.getChildCount(); i++) {
            View v = mTabButtonContainer.getChildAt(i);
            if (v instanceof Button) {
                v.setAlpha(i == index ? 1f : 0.6f);
            }
        }
    }

    /**
     * Initializes tab navigation.
     */
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ((SyncthingApp) getApplication()).component().inject(this);
        if (!PermissionUtil.haveStoragePermission(this)) {
            requestStoragePermission();
        }
        setContentView(R.layout.activity_main);
        mDrawerLayout = findViewById(R.id.drawer_layout);
        mTabButtonContainer = findViewById(R.id.tabButtonContainer);
        FragmentManager fm = getSupportFragmentManager();
        if (savedInstanceState != null) {
            mFolderListFragment = (FolderListFragment) fm.getFragment(
                    savedInstanceState, FolderListFragment.class.getName());
            mDrawerFragment = (DrawerFragment) fm.getFragment(
                    savedInstanceState, DrawerFragment.class.getName());
        } else {
            mFolderListFragment = new FolderListFragment();
            mDrawerFragment = new DrawerFragment();
        }
        mViewPager = findViewById(R.id.pager);
        // 移除这里的 setupTabs() 调用，等待服务状态变为 ACTIVE 后再调用
        mViewPager.addOnPageChangeListener(new ViewPager.OnPageChangeListener() {
            @Override
            public void onPageScrolled(int position, float positionOffset, int positionOffsetPixels) {}
            @Override
            public void onPageSelected(int position) {
                highlightTabButton(position);
            }
            @Override
            public void onPageScrollStateChanged(int state) {}
        });
        fm.beginTransaction().replace(R.id.drawer, mDrawerFragment).commit();
        mDrawerToggle = new Toggle(this, mDrawerLayout);
        mDrawerLayout.setDrawerLockMode(DrawerLayout.LOCK_MODE_LOCKED_CLOSED);
        mDrawerLayout.addDrawerListener(mDrawerToggle);
        setOptimalDrawerWidth(findViewById(R.id.drawer));
        
        // 启动 SyncthingService
        Intent serviceIntent = new Intent(this, SyncthingService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent);
        } else {
            startService(serviceIntent);
        }
        
        onNewIntent(getIntent());
    }

    @Override
    public void onResume() {
        // 检查存储权限，如果没有则重新申请
        if (!PermissionUtil.haveStoragePermission(this)) {
            requestStoragePermission();
            // 可选：return; // 防止后续逻辑执行
        }

        // Evaluate run conditions to detect changes made to the metered wifi flags.
        SyncthingService mSyncthingService = getService();
        if (mSyncthingService != null) {
            mSyncthingService.evaluateRunConditions();
        }
        super.onResume();
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        SyncthingService mSyncthingService = getService();
        if (mSyncthingService != null) {
            mSyncthingService.unregisterOnServiceStateChangeListener(this);
            mSyncthingService.unregisterOnServiceStateChangeListener(mFolderListFragment);
            mSyncthingService.unregisterOnServiceStateChangeListener(mDeviceListFragment);
        }
    }

    @Override
    public void onServiceConnected(ComponentName componentName, IBinder iBinder) {
        super.onServiceConnected(componentName, iBinder);
        SyncthingServiceBinder syncthingServiceBinder = (SyncthingServiceBinder) iBinder;
        SyncthingService syncthingService = syncthingServiceBinder.getService();
        syncthingService.registerOnServiceStateChangeListener(this);
        // 只遍历所有 tab fragment，注册需要监听的
        if (mFragments != null) {
            for (Fragment f : mFragments) {
                if (f instanceof SyncthingService.OnServiceStateChangeListener) {
                    syncthingService.registerOnServiceStateChangeListener((SyncthingService.OnServiceStateChangeListener) f);
                }
            }
        }
    }

    /**
     * Saves current tab index and fragment states.
     */
    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);

        FragmentManager fm = getSupportFragmentManager();
        Consumer<Fragment> putFragment = fragment -> {
            if (fragment != null && fragment.isAdded()) {
                fm.putFragment(outState, fragment.getClass().getName(), fragment);
            }
        };
        putFragment.accept(mFolderListFragment);
        putFragment.accept(mDeviceListFragment);
        putFragment.accept(mDrawerFragment);

        outState.putInt("currentTab", mViewPager.getCurrentItem());
        outState.putBoolean(BATTERY_DIALOG_DISMISSED, mBatteryOptimizationsDialog == null || !mBatteryOptimizationsDialog.isShowing());
        outState.putBoolean(IS_SHOWING_RESTART_DIALOG, mRestartDialog != null && mRestartDialog.isShowing());
        if(mQrCodeDialog != null && mQrCodeDialog.isShowing()) {
            outState.putBoolean(IS_QRCODE_DIALOG_DISPLAYED, true);
            ImageView qrCode = mQrCodeDialog.findViewById(R.id.qrcode_image_view);
            TextView deviceID = mQrCodeDialog.findViewById(R.id.device_id);
            outState.putParcelable(QRCODE_BITMAP_KEY, ((BitmapDrawable) qrCode.getDrawable()).getBitmap());
            outState.putString(DEVICEID_KEY, deviceID.getText().toString());
        }
        Util.dismissDialogSafe(mRestartDialog, this);
    }

    @Override
    protected void onPostCreate(Bundle savedInstanceState) {
        super.onPostCreate(savedInstanceState);

        mDrawerToggle.syncState();

        ActionBar actionBar = getSupportActionBar();
        if (actionBar != null) {
            actionBar.setHomeButtonEnabled(true);
        }
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        mDrawerToggle.onConfigurationChanged(newConfig);
    }

    public void showRestartDialog(){
        mRestartDialog = createRestartDialog();
        mRestartDialog.show();
    }

    private Dialog createRestartDialog(){
        return  Util.getAlertDialogBuilder(this)
                .setMessage(R.string.dialog_confirm_restart)
                .setPositiveButton(android.R.string.yes, (dialogInterface, i1) -> this.startService(new Intent(this, SyncthingService.class)
                        .setAction(SyncthingService.ACTION_RESTART)))
                .setNegativeButton(android.R.string.no, null)
                .create();
    }

    public void showQrCodeDialog(String deviceId, Bitmap qrCode) {
        @SuppressLint("InflateParams")
        View qrCodeDialogView = this.getLayoutInflater().inflate(R.layout.dialog_qrcode, null);
        TextView deviceIdTextView = qrCodeDialogView.findViewById(R.id.device_id);
        TextView shareDeviceIdTextView = qrCodeDialogView.findViewById(R.id.actionShareId);
        ImageView qrCodeImageView = qrCodeDialogView.findViewById(R.id.qrcode_image_view);

        deviceIdTextView.setText(deviceId);
        deviceIdTextView.setOnClickListener(v -> Util.copyDeviceId(this, deviceIdTextView.getText().toString()));
        shareDeviceIdTextView.setOnClickListener(v -> shareDeviceId(deviceId));
        qrCodeImageView.setImageBitmap(qrCode);

        mQrCodeDialog = Util.getAlertDialogBuilder(this)
                .setTitle(R.string.device_id)
                .setView(qrCodeDialogView)
                .setPositiveButton(R.string.finish, null)
                .create();

        mQrCodeDialog.show();
    }

    private void shareDeviceId(String deviceId) {
        Intent shareIntent = new Intent(android.content.Intent.ACTION_SEND);
        shareIntent.setType("text/plain");
        shareIntent.putExtra(android.content.Intent.EXTRA_TEXT, deviceId);
        startActivity(Intent.createChooser(shareIntent, getString(R.string.share_device_id_chooser)));
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // 不再显示右上角添加文件夹菜单
        return false;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        // 让 DrawerToggle 处理左上角菜单按钮
        if (mDrawerToggle != null && mDrawerToggle.onOptionsItemSelected(item)) {
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    /**
     * Handles drawer opened and closed events, toggling option menu state.
     */
    private class Toggle extends ActionBarDrawerToggle {
        public Toggle(Activity activity, DrawerLayout drawerLayout) {
            super(activity, drawerLayout, R.string.app_name, R.string.app_name);
        }

        @Override
        public void onDrawerOpened(View drawerView) {
            super.onDrawerOpened(drawerView);
            mDrawerFragment.onDrawerOpened();
        }

        @Override
        public void onDrawerClosed(View view) {
            super.onDrawerClosed(view);
            mDrawerFragment.onDrawerClosed();
        }

        @Override
        public void onDrawerSlide(View drawerView, float slideOffset) {
            super.onDrawerSlide(drawerView, 0);
        }
    }

    /**
     * Closes the drawer. Use when navigating away from activity.
     */
    public void closeDrawer() {
        mDrawerLayout.closeDrawer(GravityCompat.START);
    }

    /**
     * Toggles the drawer on menu button press.
     */
    @Override
    public boolean onKeyDown(int keyCode, KeyEvent e) {
        if (keyCode == KeyEvent.KEYCODE_MENU) {
            if (!mDrawerLayout.isDrawerOpen(GravityCompat.START))
                mDrawerLayout.openDrawer(GravityCompat.START);
            else
                closeDrawer();

            return true;
        }
        return super.onKeyDown(keyCode, e);
    }

    @Override
    public void onBackPressed() {
        if (mDrawerLayout.isDrawerOpen(GravityCompat.START)) {
            // Close drawer on back button press.
            closeDrawer();
        } else {
            /**
             * Leave MainActivity in its state as the home button was pressed.
             * This will avoid waiting for the loading spinner when getting back
             * and give changes to do UI updates based on EventProcessor in the future.
             */
            moveTaskToBack(true);
        }
    }

    /**
     * Calculating width based on
     * http://www.google.com/design/spec/patterns/navigation-drawer.html#navigation-drawer-specs.
     */
    private void setOptimalDrawerWidth(View drawerContainer) {
        int actionBarSize = 0;
        TypedValue tv = new TypedValue();
        if (getTheme().resolveAttribute(android.R.attr.actionBarSize, tv, true)) {
            actionBarSize = TypedValue.complexToDimensionPixelSize(tv.data,getResources().getDisplayMetrics());
        }

        ViewGroup.LayoutParams params = drawerContainer.getLayoutParams();
        DisplayMetrics displayMetrics = getResources().getDisplayMetrics();
        int minScreenWidth = min(displayMetrics.widthPixels, displayMetrics.heightPixels);

        params.width = min(minScreenWidth - actionBarSize, 5 * actionBarSize);
        drawerContainer.requestLayout();
    }

    /**
     * Displays dialog asking user to accept/deny usage reporting.
     */
    private void showUsageReportingDialog(RestApi restApi) {
        final DialogInterface.OnClickListener listener = (dialog, which) -> {
            try {
                switch (which) {
                    case DialogInterface.BUTTON_POSITIVE:
                        restApi.setUsageReporting(true);
                        restApi.saveConfigAndRestart();
                        break;
                    case DialogInterface.BUTTON_NEGATIVE:
                        restApi.setUsageReporting(false);
                        restApi.saveConfigAndRestart();
                        break;
                    case DialogInterface.BUTTON_NEUTRAL:
                        Uri uri = Uri.parse("https://data.syncthing.net");
                        startActivity(new Intent(Intent.ACTION_VIEW, uri));
                        break;
                }
            } catch (Exception e) {
                Log.e(TAG, "showUsageReportingDialog:OnClickListener", e);
            }
        };

        restApi.getUsageReport(report -> {
            @SuppressLint("InflateParams")
            View v = LayoutInflater.from(MainActivity.this)
                    .inflate(R.layout.dialog_usage_reporting, null);
            TextView tv = v.findViewById(R.id.example);
            tv.setText(report);
            Util.getAlertDialogBuilder(MainActivity.this)
                    .setTitle(R.string.usage_reporting_dialog_title)
                    .setView(v)
                    .setPositiveButton(R.string.yes, listener)
                    .setNegativeButton(R.string.no, listener)
                    .setNeutralButton(R.string.open_website, listener)
                    .show();
        });
    }

    // 权限请求相关方法，参考 FirstStartActivity
    private void requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            requestAllFilesAccessPermission();
        } else {
            androidx.core.app.ActivityCompat.requestPermissions(this,
                    new String[]{android.Manifest.permission.WRITE_EXTERNAL_STORAGE},
                    com.nutomic.syncthingandroid.service.Constants.PermissionRequestType.STORAGE.ordinal());
        }
    }

    @android.annotation.TargetApi(30)
    private void requestAllFilesAccessPermission() {
        Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
        intent.setData(Uri.parse("package:" + getPackageName()));
        try {
            ComponentName componentName = intent.resolveActivity(getPackageManager());
            if (componentName != null) {
                startActivity(intent);
                return;
            }
            Log.w(TAG, "Request all files access not supported");
        } catch (ActivityNotFoundException e) {
            Log.w(TAG, "Request all files access not supported", e);
        }
        Toast.makeText(this, R.string.dialog_all_files_access_not_supported, Toast.LENGTH_LONG).show();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @androidx.annotation.NonNull String[] permissions, @androidx.annotation.NonNull int[] grantResults) {
        if (requestCode == com.nutomic.syncthingandroid.service.Constants.PermissionRequestType.STORAGE.ordinal()) {
            if (grantResults.length == 0 || grantResults[0] != PackageManager.PERMISSION_GRANTED) {
                Log.i(TAG, "User denied WRITE_EXTERNAL_STORAGE permission.");
            } else {
                Toast.makeText(this, R.string.permission_granted, Toast.LENGTH_SHORT).show();
                Log.i(TAG, "User granted WRITE_EXTERNAL_STORAGE permission.");
            }
        } else {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        }
    }

}
