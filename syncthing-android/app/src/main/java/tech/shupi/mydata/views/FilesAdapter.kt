package tech.shupi.mydata.views

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.ImageView
import android.widget.TextView
import com.nutomic.syncthingandroid.R
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
        } else {
            iconImageView.setImageResource(R.drawable.ic_file)
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
}