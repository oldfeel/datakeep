package com.nutomic.syncthingandroid.activities;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.nutomic.syncthingandroid.R;
import com.nutomic.syncthingandroid.util.HttpClient;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class FolderDetailActivity extends AppCompatActivity {
    private static final String TAG = "FolderDetailActivity";
    private static final String EXTRA_DEVICE_ID = "device_id";
    private static final String EXTRA_FOLDER_ID = "folder_id";
    private static final String EXTRA_FOLDER_LABEL = "folder_label";
    private static final String EXTRA_CURRENT_PATH = "current_path";
    
    private String mDeviceId;
    private String mFolderId;
    private String mFolderLabel;
    private String mCurrentPath;
    private HttpClient mHttpClient;
    private RecyclerView mFilesRecyclerView;
    private FileAdapter mFileAdapter;
    private List<FileItem> mFiles = new ArrayList<>();
    
    public static Intent newIntent(Context context, String deviceId, String folderId, String folderLabel) {
        Intent intent = new Intent(context, FolderDetailActivity.class);
        intent.putExtra(EXTRA_DEVICE_ID, deviceId);
        intent.putExtra(EXTRA_FOLDER_ID, folderId);
        intent.putExtra(EXTRA_FOLDER_LABEL, folderLabel);
        return intent;
    }
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.d(TAG, "onCreate: 开始创建FolderDetailActivity");
        setContentView(R.layout.activity_folder_detail);
        Log.d(TAG, "onCreate: 设置布局完成");
        
        // 设置Toolbar
        androidx.appcompat.widget.Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        Log.d(TAG, "onCreate: 设置Toolbar完成");
        
        // 获取传递的参数
        mDeviceId = getIntent().getStringExtra(EXTRA_DEVICE_ID);
        mFolderId = getIntent().getStringExtra(EXTRA_FOLDER_ID);
        mFolderLabel = getIntent().getStringExtra(EXTRA_FOLDER_LABEL);
        mCurrentPath = getIntent().getStringExtra(EXTRA_CURRENT_PATH);
        
        Log.d(TAG, "onCreate: 获取参数 - deviceId=" + mDeviceId + 
                   ", folderId=" + mFolderId + 
                   ", folderLabel=" + mFolderLabel + 
                   ", currentPath=" + mCurrentPath);
        
        if (mCurrentPath == null) {
            mCurrentPath = "";
            Log.d(TAG, "onCreate: currentPath为null，设置为空字符串");
        }
        
        // 设置标题和返回按钮
        setTitle(mFolderLabel != null ? mFolderLabel : mFolderId);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            Log.d(TAG, "onCreate: 设置返回按钮成功");
        } else {
            Log.w(TAG, "onCreate: getSupportActionBar()返回null");
        }
        
        // 初始化RecyclerView
        mFilesRecyclerView = findViewById(R.id.files_recycler_view);
        if (mFilesRecyclerView == null) {
            Log.e(TAG, "onCreate: 找不到files_recycler_view");
            return;
        }
        Log.d(TAG, "onCreate: 找到RecyclerView");
        
        mFilesRecyclerView.setLayoutManager(new LinearLayoutManager(this));
        mFileAdapter = new FileAdapter();
        mFilesRecyclerView.setAdapter(mFileAdapter);
        Log.d(TAG, "onCreate: RecyclerView初始化完成");
        
        // 设置点击事件
        mFileAdapter.setOnItemClickListener(file -> {
            Log.d(TAG, "onCreate: 文件点击事件 - file=" + file.name + ", isDir=" + file.isDir);
            if (file.isDir) {
                // 进入子目录
                String newPath = mCurrentPath.isEmpty() ? file.name : mCurrentPath + "/" + file.name;
                Log.d(TAG, "onCreate: 进入子目录 - newPath=" + newPath);
                Intent intent = new Intent(this, FolderDetailActivity.class);
                intent.putExtra(EXTRA_DEVICE_ID, mDeviceId);
                intent.putExtra(EXTRA_FOLDER_ID, mFolderId);
                intent.putExtra(EXTRA_FOLDER_LABEL, mFolderLabel);
                intent.putExtra(EXTRA_CURRENT_PATH, newPath);
                startActivity(intent);
            } else {
                // 文件点击处理（可以添加文件预览功能）
                Log.d(TAG, "onCreate: 文件点击 - " + file.name);
                Toast.makeText(this, "文件: " + file.name, Toast.LENGTH_SHORT).show();
            }
        });
        
        Log.d(TAG, "onCreate: 开始加载文件列表");
        // 加载文件列表
        loadFiles();
    }
    
    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.folder_detail_menu, menu);
        return true;
    }
    
    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == android.R.id.home) {
            // 返回按钮
            onBackPressed();
            return true;
        } else if (item.getItemId() == R.id.action_edit) {
            // 编辑按钮
            Intent intent = new Intent(this, FolderActivity.class);
            intent.putExtra(FolderActivity.EXTRA_FOLDER_ID, mFolderId);
            intent.putExtra(FolderActivity.EXTRA_FOLDER_LABEL, mFolderLabel);
            intent.putExtra(FolderActivity.EXTRA_DEVICE_ID, mDeviceId);
            intent.putExtra(FolderActivity.EXTRA_IS_CREATE, false);
            startActivity(intent);
            return true;
        }
        return super.onOptionsItemSelected(item);
    }
    
    private void loadFiles() {
        Log.d(TAG, "loadFiles: 开始加载文件列表");
        if (mHttpClient == null) {
            mHttpClient = new HttpClient();
            Log.d(TAG, "loadFiles: 创建新的HttpClient");
        }
        
        String endpoint = "/api/folder/" + mFolderId;
        if (!mCurrentPath.isEmpty()) {
            endpoint += "?path=" + mCurrentPath;
        }
        
        Log.i(TAG, "loadFiles: GET " + endpoint + " - 获取文件夹文件列表");
        
        mHttpClient.get(endpoint, new okhttp3.Callback() {
            @Override
            public void onResponse(okhttp3.Call call, okhttp3.Response response) throws IOException {
                Log.d(TAG, "loadFiles: onResponse - status=" + response.code() + ", success=" + response.isSuccessful());
                if (response.isSuccessful()) {
                    String responseBody = response.body().string();
                    Log.d(TAG, "loadFiles: 响应内容长度=" + responseBody.length());
                    Log.d(TAG, "loadFiles: 响应内容=" + responseBody);
                    
                    try {
                        JSONObject jsonResponse = new JSONObject(responseBody);
                        JSONArray files;
                        
                        // 检查响应格式
                        if (jsonResponse.has("code") && jsonResponse.has("data")) {
                            int code = jsonResponse.getInt("code");
                            Log.d(TAG, "loadFiles: API响应code=" + code);
                            if (code != 0) {
                                String errorMsg = jsonResponse.optString("data", "未知错误");
                                Log.e(TAG, "loadFiles: API 返回错误: code=" + code + ", message=" + errorMsg);
                                runOnUiThread(() -> {
                                    Toast.makeText(FolderDetailActivity.this, "API 错误: " + errorMsg, Toast.LENGTH_SHORT).show();
                                });
                                return;
                            }
                            files = jsonResponse.getJSONArray("data");
                            Log.d(TAG, "loadFiles: 从data字段获取文件数组，长度=" + files.length());
                        } else if (jsonResponse.has("files")) {
                            files = jsonResponse.getJSONArray("files");
                            Log.d(TAG, "loadFiles: 从files字段获取文件数组，长度=" + files.length());
                        } else {
                            Log.e(TAG, "loadFiles: 未知的响应格式: " + responseBody);
                            return;
                        }
                        
                        // 解析文件列表
                        List<FileItem> fileList = new ArrayList<>();
                        for (int i = 0; i < files.length(); i++) {
                            JSONObject fileJson = files.getJSONObject(i);
                            FileItem file = new FileItem();
                            file.id = fileJson.optInt("id", 0);
                            file.folderId = fileJson.optString("folderId", "");
                            file.path = fileJson.optString("path", "");
                            file.name = fileJson.optString("name", "");
                            file.size = fileJson.optLong("size", 0);
                            file.modTime = fileJson.optLong("modTime", 0);
                            file.isDir = fileJson.optBoolean("isDir", false);
                            fileList.add(file);
                            Log.d(TAG, "loadFiles: 解析文件 " + i + " - name=" + file.name + ", isDir=" + file.isDir + ", size=" + file.size);
                        }
                        
                        Log.d(TAG, "loadFiles: 解析完成，文件总数=" + fileList.size());
                        
                        // 在主线程更新UI
                        runOnUiThread(() -> {
                            Log.d(TAG, "loadFiles: 在主线程更新UI");
                            mFiles.clear();
                            mFiles.addAll(fileList);
                            Log.d(TAG, "loadFiles: 设置适配器数据，文件数=" + mFiles.size());
                            mFileAdapter.setFiles(mFiles);
                            Log.d(TAG, "loadFiles: 通知适配器数据变化完成");
                        });
                        
                    } catch (Exception e) {
                        Log.e(TAG, "loadFiles: 解析文件信息失败", e);
                        runOnUiThread(() -> {
                            Toast.makeText(FolderDetailActivity.this, "解析文件信息失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
                        });
                    }
                } else {
                    Log.e(TAG, "loadFiles: 获取文件列表失败: " + response.code());
                    runOnUiThread(() -> {
                        Toast.makeText(FolderDetailActivity.this, "获取文件列表失败: " + response.code(), Toast.LENGTH_SHORT).show();
                    });
                }
            }
            
            @Override
            public void onFailure(okhttp3.Call call, IOException e) {
                Log.e(TAG, "loadFiles: 获取文件列表失败: " + e.getMessage(), e);
                runOnUiThread(() -> {
                    Toast.makeText(FolderDetailActivity.this, "获取文件列表失败: " + e.getMessage(), Toast.LENGTH_SHORT).show();
                });
            }
        });
    }
    
    // 文件数据类
    private static class FileItem {
        int id;
        String folderId;
        String path;
        String name;
        long size;
        long modTime;
        boolean isDir;
    }
    
    // 文件适配器
    private static class FileAdapter extends RecyclerView.Adapter<FileAdapter.ViewHolder> {
        private static final String TAG = "FileAdapter";
        private List<FileItem> files = new ArrayList<>();
        private OnItemClickListener listener;
        
        public interface OnItemClickListener {
            void onItemClick(FileItem file);
        }
        
        public void setOnItemClickListener(OnItemClickListener listener) {
            this.listener = listener;
            Log.d(TAG, "setOnItemClickListener: 设置点击监听器");
        }
        
        public void setFiles(List<FileItem> files) {
            Log.d(TAG, "setFiles: 设置文件列表，数量=" + files.size());
            this.files.clear();
            this.files.addAll(files);
            Log.d(TAG, "setFiles: 更新内部列表完成，数量=" + this.files.size());
            notifyDataSetChanged();
        }
        
        @NonNull
        @Override
        public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            Log.d(TAG, "onCreateViewHolder: 创建ViewHolder");
            View view = LayoutInflater.from(parent.getContext())
                    .inflate(android.R.layout.simple_list_item_2, parent, false);
            return new ViewHolder(view);
        }
        
        @Override
        public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
            FileItem file = files.get(position);
            Log.d(TAG, "onBindViewHolder: 绑定位置 " + position + " - 文件=" + file.name);
            
            // 设置文件名
            String fileName = file.isDir ? "📁 " + file.name : "📄 " + file.name;
            holder.text1.setText(fileName);
            
            // 设置文件信息
            StringBuilder info = new StringBuilder();
            if (file.isDir) {
                info.append("文件夹");
            } else {
                info.append("文件 • ").append(formatFileSize(file.size));
            }
            info.append(" • ").append(formatDate(file.modTime));
            holder.text2.setText(info.toString());
            
            // 设置点击事件
            holder.itemView.setOnClickListener(v -> {
                Log.d(TAG, "onBindViewHolder: 文件被点击 - " + file.name);
                if (listener != null) {
                    listener.onItemClick(file);
                }
            });
        }
        
        @Override
        public int getItemCount() {
            Log.d(TAG, "getItemCount: 返回文件数量=" + files.size());
            return files.size();
        }
        
        private String formatFileSize(long size) {
            if (size == 0) return "0 B";
            String[] units = {"B", "KB", "MB", "GB", "TB"};
            int digitGroups = (int) (Math.log10(size) / Math.log10(1024));
            return String.format(Locale.getDefault(), "%.1f %s", 
                    size / Math.pow(1024, digitGroups), units[digitGroups]);
        }
        
        private String formatDate(long timestamp) {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault());
            return sdf.format(new Date(timestamp * 1000));
        }
        
        static class ViewHolder extends RecyclerView.ViewHolder {
            TextView text1;
            TextView text2;
            
            ViewHolder(View itemView) {
                super(itemView);
                text1 = itemView.findViewById(android.R.id.text1);
                text2 = itemView.findViewById(android.R.id.text2);
            }
        }
    }
} 