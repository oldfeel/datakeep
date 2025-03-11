package tech.shupi.mydata

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import com.nutomic.syncthingandroid.R
import com.nutomic.syncthingandroid.databinding.ActivityMain2Binding
import com.nutomic.syncthingandroid.service.RestApi
import com.nutomic.syncthingandroid.service.SyncthingService
import com.nutomic.syncthingandroid.service.SyncthingServiceBinder
import tech.shupi.mydata.base.BaseServiceFragment
import tech.shupi.mydata.fragments.MainFilesFragment
import tech.shupi.mydata.fragments.MainRecordsFragment
import tech.shupi.mydata.fragments.MainSettingsFragment
import tech.shupi.mydata.fragments.MainTasksFragment

class MainActivity2 : AppCompatActivity(), SyncthingService.OnServiceStateChangeListener {

    private lateinit var binding: ActivityMain2Binding
    private var syncthingService: SyncthingService? = null

    private var mainFilesFragment: MainFilesFragment? = null
    private var mainRecordsFragment: MainRecordsFragment? = null
    private var mainTasksFragment: MainTasksFragment? = null
    private var mainSettingsFragment: MainSettingsFragment? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        binding = ActivityMain2Binding.inflate(layoutInflater)
        setContentView(binding.root)

        startSyncthingService()
        initListener()

        // 默认显示 mainFilesFragment
        if (savedInstanceState == null) {
            mainFilesFragment = MainFilesFragment()
            supportFragmentManager.beginTransaction()
                .replace(R.id.main_content, mainFilesFragment!!).commit()
            updateButtonState(binding.mainFiles)
        }
    }

    private fun startSyncthingService() {
        val serviceIntent = Intent(this, SyncthingService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as SyncthingServiceBinder
            syncthingService = binder.service

            registerStateChangeListener()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            syncthingService = null
        }
    }

    private fun registerStateChangeListener() {
        syncthingService?.registerOnServiceStateChangeListener(this@MainActivity2)

        syncthingService?.registerOnServiceStateChangeListener(mainFilesFragment)
    }

    private fun initListener() {
        binding.mainFiles.setOnClickListener {
            if (mainFilesFragment == null) {
                mainFilesFragment = MainFilesFragment()
            }
            switchFragment(mainFilesFragment!!)
            updateButtonState(binding.mainFiles)
        }
        binding.mainTasks.setOnClickListener {
            if (mainTasksFragment == null) {
                mainTasksFragment = MainTasksFragment()
            }
            switchFragment(mainTasksFragment!!)
            updateButtonState(binding.mainTasks)
        }
        binding.mainRecords.setOnClickListener {
            if (mainRecordsFragment == null) {
                mainRecordsFragment = MainRecordsFragment()
            }
            switchFragment(mainRecordsFragment!!)
            updateButtonState(binding.mainRecords)
        }
        binding.mainSettings.setOnClickListener {
            if (mainSettingsFragment == null) {
                mainSettingsFragment = MainSettingsFragment()
            }
            switchFragment(mainSettingsFragment!!)
            updateButtonState(binding.mainSettings)
        }
    }

    private fun switchFragment(fragment: BaseServiceFragment) {
        supportFragmentManager.beginTransaction().replace(R.id.main_content, fragment).commit()

        syncthingService?.registerOnServiceStateChangeListener(fragment)
    }

    private fun updateButtonState(selectedButton: View) {
        // 重置所有按钮的状态
        binding.mainFiles.isSelected = false
        binding.mainTasks.isSelected = false
        binding.mainRecords.isSelected = false
        binding.mainSettings.isSelected = false

        // 设置选中按钮的状态
        selectedButton.isSelected = true
    }

    override fun onServiceStateChange(currentState: SyncthingService.State) {
    }

    override fun onDestroy() {
        super.onDestroy()
        syncthingService?.unregisterOnServiceStateChangeListener(this)
        unbindService(serviceConnection)
    }

    fun getApi(): RestApi? {
        return syncthingService!!.api
    }
}