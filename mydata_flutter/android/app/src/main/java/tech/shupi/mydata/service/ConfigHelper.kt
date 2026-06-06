package tech.shupi.mydata.service

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Log

/** 修正 Syncthing config.xml 中的本机设备名称（Android 默认 hostname 常为 localhost） */
object ConfigHelper {
    private const val TAG = "ConfigHelper"

    /** 使用系统设备名或 Build.MODEL（获取到什么就显示什么，如 XT2175-2） */
    fun getPhoneDeviceName(context: Context): String {
        val system = readSystemDeviceName(context)
        val model = Build.MODEL?.trim().orEmpty()

        val chosen = when {
            system != null -> system
            model.isNotEmpty() && !model.equals("localhost", ignoreCase = true) ->
                sanitizeName(formatDisplayName(model))
            else -> {
                val manufacturer = Build.MANUFACTURER?.trim().orEmpty()
                if (manufacturer.isNotEmpty()) {
                    sanitizeName(formatDisplayName(manufacturer))
                } else {
                    "Android 手机"
                }
            }
        }
        Log.i(TAG, "设备名: DEVICE_NAME=$system, MODEL=$model => $chosen")
        return chosen
    }

    private fun readSystemDeviceName(context: Context): String? {
        return try {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
                ?.trim()
                ?.takeIf { isUsableName(it) && !isGenericAndroidName(it) }
        } catch (e: Exception) {
            Log.w(TAG, "读取 DEVICE_NAME 失败", e)
            null
        }
    }

    private fun isUsableName(name: String): Boolean {
        return name.isNotEmpty() && !name.equals("localhost", ignoreCase = true)
    }

    private fun isGenericAndroidName(name: String): Boolean {
        return name.equals("Android", ignoreCase = true)
    }

    private fun formatDisplayName(raw: String): String {
        return raw.split(Regex("\\s+"))
            .joinToString(" ") { word ->
                word.replaceFirstChar { c ->
                    if (c.isLowerCase()) c.titlecase() else c.toString()
                }
            }
    }

    private fun sanitizeName(name: String): String {
        return name.replace(Regex("[\"<>]"), "").take(32).trim()
    }

    /**
     * 若本机设备名为 localhost/空，则写入系统型号。
     * 需在 Syncthing MAIN 启动前调用；config 不存在时跳过。
     */
    fun ensureLocalDeviceName(context: Context) {
        val configFile = Constants.getConfigFile(context)
        if (!configFile.exists()) {
            Log.i(TAG, "config.xml 不存在，跳过设备名修正")
            return
        }

        val phoneName = getPhoneDeviceName(context)
        val xml = configFile.readText()
        val updated = patchFirstDeviceName(xml, phoneName)
        if (updated != null) {
            configFile.writeText(updated)
            Log.i(TAG, "本机 Syncthing 设备名已设为: $phoneName")
        } else {
            val firstName = Regex("""\bname="([^"]*)"""").find(
                Regex("""<device\s+([^>]+)>""").find(xml)?.groupValues?.get(1) ?: ""
            )?.groupValues?.get(1) ?: "(无)"
            Log.i(TAG, "config 本机设备名无需修改，当前: $firstName, 目标: $phoneName")
        }
    }

    /** 确保 config 存在（首次安装时先 -generate） */
    fun ensureConfigExists(context: Context) {
        val configFile = Constants.getConfigFile(context)
        if (configFile.exists()) return

        val binary = Constants.getSyncthingBinary(context)
        if (!binary.exists()) {
            Log.w(TAG, "Syncthing 二进制不存在，无法生成配置")
            return
        }

        Log.i(TAG, "首次运行，生成 Syncthing 配置…")
        try {
            val homeDir = context.filesDir.toString()
            ProcessBuilder(binary.path, "-generate", homeDir, "-logflags=0")
                .redirectErrorStream(true)
                .start()
                .waitFor()
            ensureLocalDeviceName(context)
        } catch (e: Exception) {
            Log.e(TAG, "生成 Syncthing 配置失败", e)
        }
    }

    private fun patchFirstDeviceName(xml: String, newName: String): String? {
        val deviceTag = Regex("""<device\s+([^>]+)>""").find(xml) ?: return null
        val attrs = deviceTag.groupValues[1]

        val idMatch = Regex("""\bid="([^"]+)"""").find(attrs)
        val deviceId = idMatch?.groupValues?.get(1) ?: return null

        val nameMatch = Regex("""\bname="([^"]*)"""").find(attrs)
        val currentName = nameMatch?.groupValues?.get(1)?.trim().orEmpty()
        if (!isPlaceholderName(currentName, deviceId)) {
            return null
        }
        if (currentName.equals(newName, ignoreCase = true)) {
            return null
        }

        val newAttrs = if (nameMatch != null) {
            attrs.replace(Regex("""\bname="[^"]*""""), """name="$newName"""")
        } else {
            """$attrs name="$newName""""
        }

        return xml.replaceFirst("""<device\s+${Regex.escape(attrs)}>""", """<device $newAttrs>""")
    }

    /** localhost、空名、设备 ID 或其短前缀 */
    private fun isPlaceholderName(name: String, deviceId: String): Boolean {
        if (name.isEmpty()) return true
        if (name.equals("localhost", ignoreCase = true)) return true
        if (name.equals("unknown", ignoreCase = true)) return true
        val normId = deviceId.replace(Regex("[\\s-]"), "").uppercase()
        val normName = name.replace(Regex("[\\s-]"), "").uppercase()
        if (normName == normId) return true
        val shortId = deviceId.substringBefore('-').uppercase()
        if (name.uppercase() == shortId) return true
        return false
    }
}
