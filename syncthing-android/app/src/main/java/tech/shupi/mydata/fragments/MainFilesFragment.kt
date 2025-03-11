package tech.shupi.mydata.fragments

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.Menu
import android.view.MenuInflater
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.AdapterView.OnItemClickListener
import com.nutomic.syncthingandroid.databinding.FragmentMainFilesBinding
import com.nutomic.syncthingandroid.databinding.FragmentMainTasksBinding
import tech.shupi.mydata.base.BaseFragment
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import com.google.gson.Gson
import com.nutomic.syncthingandroid.R
import com.nutomic.syncthingandroid.activities.DeviceActivity
import com.nutomic.syncthingandroid.model.Device
import com.nutomic.syncthingandroid.service.Constants
import com.nutomic.syncthingandroid.service.SyncthingService
import com.nutomic.syncthingandroid.service.SyncthingService.OnServiceStateChangeListener
import com.nutomic.syncthingandroid.views.DevicesAdapter
import tech.shupi.mydata.MainActivity2
import tech.shupi.mydata.base.BaseConstants.TAG
import tech.shupi.mydata.base.BaseServiceFragment
import tech.shupi.mydata.views.DevicesAdapter2
import java.util.Collections
import java.util.Timer
import java.util.TimerTask

class MainFilesFragment : BaseServiceFragment(), OnItemClickListener {
    private lateinit var binding: FragmentMainFilesBinding

    private val DEVICES_COMPARATOR = Comparator<Device> { lhs, rhs -> lhs.name.compareTo(rhs.name) }

    private var mAdapter: DevicesAdapter2? = null
    private var mTimer: Timer? = null

    override fun onPause() {
        super.onPause()
        mTimer?.cancel()
    }

    override fun onServiceStateChange(currentState: SyncthingService.State) {
        Log.d(TAG, "mainFilesFragment onServiceStateChange: start")
        if (currentState != SyncthingService.State.ACTIVE) return

        mTimer = Timer()
        mTimer?.schedule(object : TimerTask() {
            override fun run() {
                if (activity == null) return

                activity?.runOnUiThread { updateList() }
            }
        }, 0, Constants.GUI_UPDATE_INTERVAL)
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View {
        binding = FragmentMainFilesBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        setTitle("文件")
        setHasOptionsMenu(true)

        binding.deviceList.onItemClickListener = this
    }

    override fun onCreateOptionsMenu(menu: Menu, inflater: MenuInflater) {
        inflater.inflate(R.menu.menu_main_file, menu)
        super.onCreateOptionsMenu(menu, inflater)
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_add_device -> {
                addDevice()
                true
            }

            R.id.action_add_file -> {
                addFile()
                true
            }

            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun addFile() {

    }

    private fun addDevice() {
        val intent = Intent(activity, DeviceActivity::class.java).putExtra(
            DeviceActivity.EXTRA_IS_CREATE, true
        )
        startActivity(intent)
    }

    /**
     * Refreshes ListView by updating devices and info.
     *
     * Also creates adapter if it doesn't exist yet.
     */
    private fun updateList() {
        Log.d(TAG, "updateList: start")
        val activity = this.activity as? MainActivity2 ?: return
        if (view == null || activity.isFinishing) return

        val restApi = activity.getApi() ?: return
        if (!restApi.isConfigLoaded()) return

        val devices = restApi.getDevices(false) ?: return

        Log.d(TAG, "updateList: devices " + devices.size + " " + Gson().toJson(devices))

        if (mAdapter == null) {
            mAdapter = DevicesAdapter2(activity)
            binding.deviceList.adapter = mAdapter
        }

        // Prevent scroll position reset due to list update from clear().
        mAdapter?.setNotifyOnChange(false)
        mAdapter?.clear()
        Collections.sort(devices, DEVICES_COMPARATOR)
        mAdapter?.addAll(devices)
        mAdapter?.updateConnections(restApi)
        mAdapter?.notifyDataSetChanged()
    }

    override fun onItemClick(parent: AdapterView<*>, view: View, position: Int, id: Long) {
        val intent = Intent(activity, DeviceActivity::class.java)
        intent.putExtra(DeviceActivity.EXTRA_IS_CREATE, false)
        intent.putExtra(DeviceActivity.EXTRA_DEVICE_ID, mAdapter?.getItem(position)?.deviceID)
        startActivity(intent)
    }
}