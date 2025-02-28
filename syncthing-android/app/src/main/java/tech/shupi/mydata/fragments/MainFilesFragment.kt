package tech.shupi.mydata.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.nutomic.syncthingandroid.databinding.FragmentMainFilesBinding
import com.nutomic.syncthingandroid.databinding.FragmentMainTasksBinding
import tech.shupi.mydata.base.BaseFragment
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import com.nutomic.syncthingandroid.R

class MainFilesFragment : BaseFragment() {
    private lateinit var binding: FragmentMainFilesBinding

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        binding = FragmentMainFilesBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        setTitle("Main Files")
    }
}