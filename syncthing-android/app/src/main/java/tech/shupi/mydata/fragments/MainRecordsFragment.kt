package tech.shupi.mydata.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.nutomic.syncthingandroid.databinding.FragmentMainRecordsBinding
import com.nutomic.syncthingandroid.databinding.FragmentMainTasksBinding
import tech.shupi.mydata.base.BaseFragment

class MainRecordsFragment : BaseFragment() {
    private lateinit var binding: FragmentMainRecordsBinding

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        binding = FragmentMainRecordsBinding.inflate(inflater, container, false)
        return binding.root
    }
}