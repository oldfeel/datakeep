package tech.shupi.mydata.views

import android.content.Context
import android.content.res.Resources
import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.google.android.material.color.MaterialColors
import com.nutomic.syncthingandroid.R
import com.nutomic.syncthingandroid.model.Connections
import com.nutomic.syncthingandroid.model.Device
import com.nutomic.syncthingandroid.service.RestApi
import com.nutomic.syncthingandroid.util.Util

/**
 * Generates item views for device items.
 */
class DevicesAdapter2(context: Context) : ArrayAdapter<Device>(context, R.layout.item_devices) {

    private var mConnections: Connections? = null

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val view = convertView ?: LayoutInflater.from(context)
            .inflate(R.layout.item_devices, parent, false)

        val icon = view.findViewById<ImageView>(R.id.device_icon)
        val name = view.findViewById<TextView>(R.id.device_name)
        val status = view.findViewById<TextView>(R.id.device_status)
        val syncStatus = view.findViewById<TextView>(R.id.device_sync_status)

        val device = getItem(position)
        val deviceId = device?.deviceID ?: ""

        name.text = device?.getDisplayName()

        // Set device icon based on type
//        if (device?.isPhone == true) {
//            icon.setImageResource(R.drawable.ic_phone) // Ensure you have this drawable
//        } else {
//            icon.setImageResource(R.drawable.ic_computer) // Ensure you have this drawable
//        }
        icon.setImageResource(R.drawable.icon_pc)

        val conn = mConnections?.connections?.get(deviceId)

        if (conn == null) {
            status.text = context.getString(R.string.device_state_unknown)
            status.setTextColor(ContextCompat.getColor(context, R.color.text_red))
            syncStatus.text = ""
            return view
        }

        if (conn.paused) {
            status.text = context.getString(R.string.device_paused)
            status.setTextColor(
                MaterialColors.getColor(
                    context,
                    android.R.attr.textColorPrimary,
                    Color.BLACK
                )
            )
            syncStatus.text = ""
            return view
        }

        if (conn.connected) {
            status.text = "在线"
            status.setTextColor(ContextCompat.getColor(context, R.color.text_green))
            if (conn.completion == 100) {
                syncStatus.text = context.getString(R.string.device_up_to_date)
            } else {
                syncStatus.text = context.getString(R.string.device_syncing, conn.completion)
            }
            return view
        }

        // !conn.connected
        status.text = context.getString(R.string.device_disconnected)
        status.setTextColor(ContextCompat.getColor(context, R.color.text_red))
        syncStatus.text = ""
        return view
    }

    /**
     * Requests new connection info for all devices visible in listView.
     */
    fun updateConnections(api: RestApi) {
        for (i in 0 until count) {
            api.getConnections { connections -> onReceiveConnections(connections) }
        }
    }

    private fun onReceiveConnections(connections: Connections) {
        mConnections = connections
        notifyDataSetChanged()
    }
}