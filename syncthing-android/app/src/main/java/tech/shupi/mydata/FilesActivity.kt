package tech.shupi.mydata

import android.os.Bundle
import com.nutomic.syncthingandroid.databinding.ActivityFilesBinding
import tech.shupi.mydata.base.BaseActivity
import tech.shupi.mydata.views.FilesAdapter
import java.io.File

class FilesActivity : BaseActivity() {
    private lateinit var bind: ActivityFilesBinding
    private lateinit var adapter: FilesAdapter
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        bind = ActivityFilesBinding.inflate(layoutInflater)
        setContentView(bind.root)

        // 初始化适配器
        adapter = FilesAdapter(this)
        bind.filesList.adapter = adapter

        // 加载文件列表示例
        loadFiles()
    }

    private fun loadFiles() {
        // 这里替换为实际的文件列表获取逻辑
        val files = mutableListOf<File>()

        // 从 intent 获取文件夹路径s
        val folderPath = intent.getStringExtra("folder_path")
        if (folderPath != null) {
            val folder = File(folderPath)
            if (folder.exists() && folder.isDirectory) {
                // 获取文件夹下的所有文件和子文件夹
                val filesList = folder.listFiles()
                if (filesList != null) {
                    files.addAll(filesList.toList())
                }
            }
        }
        
        // 更新适配器数据
        adapter.setFiles(files)
    }
}