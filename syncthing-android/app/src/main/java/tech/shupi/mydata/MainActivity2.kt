package tech.shupi.mydata

import android.os.Bundle
import com.nutomic.syncthingandroid.databinding.ActivityMain2Binding
import tech.shupi.mydata.base.BaseActivity

class MainActivity : BaseActivity() {

    private lateinit var binding: ActivityMain2Binding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        binding = ActivityMain2Binding.inflate(layoutInflater)
        setContentView(binding.root)
    }
}