package tech.shupi.mydata.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.AdapterView.OnItemClickListener
import com.nutomic.syncthingandroid.databinding.FragmentMainRecordsBinding
import com.nutomic.syncthingandroid.databinding.FragmentMainTasksBinding
import com.nutomic.syncthingandroid.service.SyncthingService
import tech.shupi.mydata.base.BaseFragment
import tech.shupi.mydata.base.BaseServiceFragment

class MainRecordsFragment : BaseServiceFragment(), OnItemClickListener {
    private lateinit var binding: FragmentMainRecordsBinding

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        binding = FragmentMainRecordsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setTitle("记录")
    }

    override fun onServiceStateChange(currentState: SyncthingService.State?) {
    }

    override fun onItemClick(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
    }
}