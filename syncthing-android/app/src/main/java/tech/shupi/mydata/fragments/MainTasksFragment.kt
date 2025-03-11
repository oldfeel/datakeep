package tech.shupi.mydata.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import com.nutomic.syncthingandroid.databinding.FragmentMainTasksBinding
import com.nutomic.syncthingandroid.service.SyncthingService
import tech.shupi.mydata.base.BaseFragment
import tech.shupi.mydata.base.BaseServiceFragment

class MainTasksFragment : BaseServiceFragment(), AdapterView.OnItemClickListener {
    private lateinit var binding: FragmentMainTasksBinding

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        binding = FragmentMainTasksBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onServiceStateChange(currentState: SyncthingService.State?) {
    }

    override fun onItemClick(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
    }
}