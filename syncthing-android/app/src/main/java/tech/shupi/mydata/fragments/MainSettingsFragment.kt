package tech.shupi.mydata.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.nutomic.syncthingandroid.databinding.FragmentMainSettingsBinding
import com.nutomic.syncthingandroid.databinding.FragmentMainTasksBinding
import tech.shupi.mydata.base.BaseFragment

class MainSettingsFragment : BaseFragment() {
    private lateinit var binding: FragmentMainSettingsBinding

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        binding = FragmentMainSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }
}