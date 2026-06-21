package tech.shupi.mydata.util

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.util.Log
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.lang.reflect.Array

/**
 * SAF URI → 绝对路径、默认同步目录、native 写权限检测。
 * 逻辑参考 Syncthing Android FileUtils / Util。
 */
object StoragePathUtils {
    private const val TAG = "StoragePathUtils"
    private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
    private const val PRIMARY_VOLUME = "primary"
    private const val HOME_VOLUME = "home"
    private const val DOWNLOADS_VOLUME = "downloads"
    private const val WRITE_TEST_FILE = ".stwritetest"

    /** 默认同步目录：Android/media/<pkg>/sync/<folderId>（native 无 All files access 时也可写） */
    fun getDefaultSyncFolderPath(context: Context, folderId: String): String {
        val mediaRoot = File(
            Environment.getExternalStorageDirectory(),
            "Android/media/${context.packageName}",
        )
        return File(mediaRoot, "sync/$folderId").absolutePath
    }

    /** SAF 选目录初始位置：Android/media/<pkg> */
    fun getInitialPickerUri(context: Context): Uri? {
        val mediaDir = File(
            Environment.getExternalStorageDirectory(),
            "Android/media/${context.packageName}",
        )
        if (!mediaDir.exists()) {
            mediaDir.mkdirs()
        }
        return Uri.parse(
            "content://$EXTERNAL_STORAGE_AUTHORITY/document/" +
                "${PRIMARY_VOLUME}%3AAndroid%2Fmedia%2F${context.packageName}",
        )
    }

    fun getAbsolutePathFromSafUri(context: Context, safUri: Uri?): String? {
        if (safUri == null) return null
        val treeUri = DocumentsContract.buildDocumentUriUsingTree(
            safUri,
            DocumentsContract.getTreeDocumentId(safUri),
        )
        return getAbsolutePathFromTreeUri(context, treeUri)
    }

    private fun getAbsolutePathFromTreeUri(context: Context, treeUri: Uri?): String? {
        if (treeUri == null) return null
        val volumeId = getVolumeIdFromTreeUri(treeUri) ?: return null
        var volumePath = getVolumePath(context, volumeId) ?: return File.separator
        if (volumePath.endsWith(File.separator)) {
            volumePath = volumePath.substring(0, volumePath.length - 1)
        }
        var documentPath = getDocumentPathFromTreeUri(treeUri)
        if (documentPath.endsWith(File.separator)) {
            documentPath = documentPath.substring(0, documentPath.length - 1)
        }
        return if (documentPath.isNotEmpty()) {
            if (documentPath.startsWith(File.separator)) {
                volumePath + documentPath
            } else {
                "$volumePath${File.separator}$documentPath"
            }
        } else {
            volumePath
        }
    }

    private fun getVolumeIdFromTreeUri(treeUri: Uri): String? {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        val split = docId.split(":")
        return split.firstOrNull()
    }

    private fun getDocumentPathFromTreeUri(treeUri: Uri): String {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        val split = docId.split(":")
        return if (split.size >= 2 && split[1].isNotEmpty()) split[1] else File.separator
    }

    @Suppress("DEPRECATION")
    private fun getVolumePath(context: Context, volumeId: String): String? {
        try {
            when (volumeId) {
                HOME_VOLUME -> {
                    return Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOCUMENTS,
                    ).absolutePath
                }
                DOWNLOADS_VOLUME -> {
                    return Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS,
                    ).absolutePath
                }
            }
            val storageManager = context.getSystemService(Context.STORAGE_SERVICE)
                ?: return fallbackVolumePath(volumeId)
            val storageVolumeClazz = Class.forName("android.os.storage.StorageVolume")
            val getVolumeList = storageManager.javaClass.getMethod("getVolumeList")
            val getUuid = storageVolumeClazz.getMethod("getUuid")
            val getPath = storageVolumeClazz.getMethod("getPath")
            val isPrimary = storageVolumeClazz.getMethod("isPrimary")
            val result = getVolumeList.invoke(storageManager)
            val length = Array.getLength(result)
            for (i in 0 until length) {
                val element = Array.get(result, i)
                val uuid = getUuid.invoke(element) as String?
                val primary = isPrimary.invoke(element) as Boolean
                val isPrimaryVolume = primary && PRIMARY_VOLUME == volumeId
                val isExternalVolume = uuid != null && uuid == volumeId
                if (isPrimaryVolume || isExternalVolume) {
                    return getPath.invoke(element) as String
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "getVolumePath exception", e)
        }
        return fallbackVolumePath(volumeId)
    }

    private fun fallbackVolumePath(volumeId: String): String? {
        if (volumeId == PRIMARY_VOLUME) {
            return Environment.getExternalStorageDirectory().absolutePath
        }
        return "/storage/$volumeId"
    }

    /** 模拟 Syncthing native 进程写文件 */
    fun nativeCanWriteToPath(absoluteFolderPath: String): Boolean {
        val touchFile = "$absoluteFolderPath/$WRITE_TEST_FILE"
        val exitCode = runShellCommand("echo \"\" > \"$touchFile\"\n")
        if (exitCode != 0) {
            Log.i(TAG, "写测试失败: $touchFile exit=$exitCode")
            return false
        }
        Log.i(TAG, "写测试成功: $touchFile")
        runShellCommand("rm \"$touchFile\"\n")
        return true
    }

    private fun runShellCommand(cmd: String): Int {
        var exitCode = 255
        try {
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
            BufferedReader(InputStreamReader(process.inputStream)).use { it.readText() }
            exitCode = process.waitFor()
        } catch (e: Exception) {
            Log.w(TAG, "runShellCommand failed", e)
        }
        return exitCode
    }

    /** 预建 .stfolder marker（Java 层辅助，与官方一致） */
    fun preCreateFolderMarker(path: String): Boolean {
        return try {
            val marker = File(path, ".stfolder")
            marker.mkdirs() || marker.exists()
        } catch (e: Exception) {
            Log.w(TAG, "preCreateFolderMarker failed", e)
            false
        }
    }
}
