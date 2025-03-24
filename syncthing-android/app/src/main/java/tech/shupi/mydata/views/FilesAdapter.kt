package tech.shupi.mydata.views

import android.content.Context
import android.content.Intent
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.FileProvider
import com.bumptech.glide.Glide
import com.nutomic.syncthingandroid.R
import tech.shupi.mydata.FilesActivity
import java.io.File

class FilesAdapter(context: Context) : BaseAdapter() {
    private var files = mutableListOf<File>()
    private var context: Context = context

    fun setFiles(newFiles: List<File>) {
        files.clear()
        files.addAll(newFiles)
        notifyDataSetChanged()
    }

    override fun getCount(): Int {
        return files.size
    }

    override fun getItem(position: Int): File {
        return files[position]
    }

    override fun getItemId(position: Int): Long {
        return position.toLong()
    }

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        var view = convertView
        if (view == null) {
            view = LayoutInflater.from(context).inflate(R.layout.item_file, parent, false)
        }

        val file = getItem(position)

        val nameTextView = view!!.findViewById<TextView>(R.id.file_name)
        val sizeTextView = view.findViewById<TextView>(R.id.file_size)
        val iconImageView = view.findViewById<ImageView>(R.id.file_icon)

        nameTextView.text = file.name
        sizeTextView.text = formatFileSize(file.length())

        if (file.isDirectory) {
            iconImageView.setImageResource(R.drawable.ic_folder)
            view.setOnClickListener {
                val intent = Intent(context, FilesActivity::class.java)
                intent.putExtra("folder_path", file.absolutePath)
                context.startActivity(intent)
            }
        } else {
            // 检查是否为图片文件
            val mimeType = getMimeType(file.name)
            when {
                mimeType.startsWith("image/") -> {
                    // 使用Glide加载图片缩略图
                    Glide.with(context)
                        .load(file)
                        .override(100, 100) // 设置缩略图大小
                        .centerCrop()
                        .into(iconImageView)
                }
                mimeType.startsWith("video/") -> {
                    iconImageView.setImageResource(R.drawable.ic_video)
                }
                else -> {
                    iconImageView.setImageResource(R.drawable.ic_file)
                }
            }
            view.setOnClickListener {
                runCatching {
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        val uri = FileProvider.getUriForFile(
                            context,
                            "${context.applicationContext.packageName}.provider",
                            file
                        )
                        val mimeType = getMimeType(file.name)
                        setDataAndType(uri, mimeType)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        Intent.createChooser(this, "请选择查看文件的应用")
                    }
                    
                    context.startActivity(intent)
                }.onFailure { e ->
                    val message = when(e) {
                        is SecurityException -> "没有权限打开此文件"
                        else -> "无法打开文件：${e.localizedMessage}"
                    }
                    Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
                }
            }
        }
        return view
    }

    private fun formatFileSize(size: Long): String {
        if (size <= 0) return "0 B"
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        val digitGroups = (Math.log10(size.toDouble()) / Math.log10(1024.0)).toInt()
        return String.format(
            "%.1f %s",
            size / Math.pow(1024.0, digitGroups.toDouble()),
            units[digitGroups]
        )
    }

    private fun getMimeType(fileName: String): String {
        return when(fileName.substringAfterLast(".", "").lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "pdf" -> "application/pdf"
            "doc", "docx" -> "application/msword"
            "xls", "xlsx" -> "application/vnd.ms-excel"
            "txt" -> "text/plain"
            "mp4" -> "video/mp4"
            "mp3" -> "audio/mp3"
            else -> "*/*"
        }
    }
}