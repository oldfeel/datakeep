package tech.shupi.mydata.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.AdapterView.OnItemClickListener
import com.nutomic.syncthingandroid.databinding.FragmentMainSettingsBinding
import com.nutomic.syncthingandroid.databinding.FragmentMainTasksBinding
import com.nutomic.syncthingandroid.service.SyncthingService
import tech.shupi.mydata.base.BaseFragment
import tech.shupi.mydata.base.BaseServiceFragment

class MainSettingsFragment : BaseServiceFragment(), OnItemClickListener {
    private lateinit var binding: FragmentMainSettingsBinding

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        binding = FragmentMainSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setTitle("设置")
    }

    override fun onServiceStateChange(currentState: SyncthingService.State?) {
    }

    override fun onItemClick(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
    }
}