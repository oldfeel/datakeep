package com.nutomic.syncthingandroid.activities;

import android.app.Activity;
import android.os.Bundle;
import android.widget.ArrayAdapter;
import android.widget.ListView;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import android.view.MenuItem;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import com.nutomic.syncthingandroid.R;

public class FileListActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_file_list);
        Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        String folderPath = getIntent().getStringExtra("folder_path");
        setTitle(folderPath);
        ListView listView = findViewById(R.id.file_list);
        List<String> fileNames = new ArrayList<>();
        if (folderPath != null) {
            File folder = new File(folderPath);
            File[] files = folder.listFiles();
            if (files != null) {
                for (File f : files) {
                    fileNames.add(f.getName() + (f.isDirectory() ? "/" : ""));
                }
            }
        }
        listView.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, fileNames));
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == android.R.id.home) {
            finish();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }
} 