package tech.shupi.mydata.base

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.fragment.app.Fragment
import com.nutomic.syncthingandroid.R

open class BaseFragment : Fragment() {
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
    }

    fun setTitle(title: String) {
        (activity as? AppCompatActivity)?.supportActionBar?.title = title
    }
}