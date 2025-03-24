package tech.shupi.mydata.views

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.text.TextUtils
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.databinding.DataBindingUtil
import com.google.android.material.color.MaterialColors
import com.nutomic.syncthingandroid.R
import com.nutomic.syncthingandroid.databinding.ItemFolderListBinding
import com.nutomic.syncthingandroid.model.Folder
import com.nutomic.syncthingandroid.model.FolderStatus
import com.nutomic.syncthingandroid.service.Constants
import com.nutomic.syncthingandroid.service.RestApi
import com.nutomic.syncthingandroid.service.SyncthingService
import com.nutomic.syncthingandroid.util.Util
import java.io.File
import android.view.View.GONE
import android.view.View.VISIBLE
import tech.shupi.mydata.FilesActivity

/**
 * Generates item views for folder items.
 */
class FoldersAdapter2(private val mContext: Context) : ArrayAdapter<Folder>(mContext, 0) {

    companion object {
        private const val TAG = "FoldersAdapter"

        /**
         * Returns the folder's state as a localized string.
         */
        private fun getLocalizedState(c: Context, folderStatus: FolderStatus): String {
            return when (folderStatus.state) {
                "idle" -> c.getString(R.string.state_idle)
                "scanning" -> c.getString(R.string.state_scanning)
                "syncing" -> {
                    val percentage = if (folderStatus.globalBytes != 0L)
                        Math.round((100 * folderStatus.inSyncBytes / folderStatus.globalBytes).toDouble())
                    else 100
                    c.getString(R.string.state_syncing, percentage)
                }
                "error" -> {
                    if (TextUtils.isEmpty(folderStatus.error)) {
                        c.getString(R.string.state_error)
                    } else {
                        "${c.getString(R.string.state_error)} (${folderStatus.error})"
                    }
                }
                "unknown" -> c.getString(R.string.state_unknown)
                else -> folderStatus.state
            }
        }
    }

    private val mLocalFolderStatuses = HashMap<String, FolderStatus>()

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val binding = if (convertView == null)
            DataBindingUtil.inflate<ItemFolderListBinding>(LayoutInflater.from(mContext), R.layout.item_folder_list, parent, false)
        else
            DataBindingUtil.bind<ItemFolderListBinding>(convertView)!!

        val folder = getItem(position)!!
        binding.label.text = if (TextUtils.isEmpty(folder.label)) folder.id else folder.label
        binding.directory.text = folder.path
        binding.override.setOnClickListener {
            // Send "Override changes" through our service to the REST API.
            val intent = Intent(mContext, SyncthingService::class.java)
                .putExtra(SyncthingService.EXTRA_FOLDER_ID, folder.id)
                .setAction(SyncthingService.ACTION_OVERRIDE_CHANGES)
            mContext.startService(intent)
        }
        binding.openFolder.setOnClickListener {
            val intent = Intent(mContext, FilesActivity::class.java).apply {
                putExtra("folder_path", folder.path)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            mContext.startActivity(intent)
        }

        updateFolderStatusView(binding, folder)
        return binding.root
    }

    private fun updateFolderStatusView(binding: ItemFolderListBinding, folder: Folder) {
        val folderStatus = mLocalFolderStatuses[folder.id]
        if (folderStatus == null) {
            binding.items.visibility = GONE
            binding.override.visibility = GONE
            binding.size.visibility = GONE
            setTextOrHide(binding.invalid, folder.invalid)
            return
        }

        val neededItems = folderStatus.needFiles + folderStatus.needDirectories + folderStatus.needSymlinks + folderStatus.needDeletes
        val outOfSync = folderStatus.state == "idle" && neededItems > 0
        val overrideButtonVisible = folder.type == Constants.FOLDER_TYPE_SEND_ONLY && outOfSync
        binding.override.visibility = if (overrideButtonVisible) VISIBLE else GONE
        
        if (outOfSync) {
            binding.state.setText(R.string.status_outofsync)
            binding.state.setTextColor(ContextCompat.getColor(mContext, R.color.text_red))
        } else {
            if (folder.paused) {
                binding.state.setText(R.string.state_paused)
                binding.state.setTextColor(MaterialColors.getColor(mContext, android.R.attr.textColorPrimary, Color.BLACK))
            } else {
                binding.state.text = getLocalizedState(mContext, folderStatus)
                binding.state.setTextColor(when (folderStatus.state) {
                    "idle" -> ContextCompat.getColor(mContext, R.color.text_green)
                    "scanning", "syncing" -> ContextCompat.getColor(mContext, R.color.text_blue)
                    else -> ContextCompat.getColor(mContext, R.color.text_red)
                })
            }
        }
        
        binding.items.visibility = VISIBLE
        binding.items.text = mContext.resources
            .getQuantityString(R.plurals.files, folderStatus.inSyncFiles.toInt(), folderStatus.inSyncFiles, folderStatus.globalFiles)
        binding.size.visibility = VISIBLE
        binding.size.text = mContext.getString(R.string.folder_size_format,
            Util.readableFileSize(mContext, folderStatus.inSyncBytes),
            Util.readableFileSize(mContext, folderStatus.globalBytes))
        setTextOrHide(binding.invalid, folderStatus.invalid)
    }

    /**
     * Requests updated folder status from the api for all visible items.
     */
    fun updateFolderStatus(api: RestApi) {
        for (i in 0 until count) {
            api.getFolderStatus(getItem(i)!!.id) { folderId, folderStatus -> 
                onReceiveFolderStatus(folderId, folderStatus)
            }
        }
    }

    private fun onReceiveFolderStatus(folderId: String, folderStatus: FolderStatus) {
        mLocalFolderStatuses[folderId] = folderStatus
        notifyDataSetChanged()
    }

    private fun setTextOrHide(view: TextView, text: String?) {
        if (TextUtils.isEmpty(text)) {
            view.visibility = GONE
        } else {
            view.text = text
            view.visibility = VISIBLE
        }
    }
}
