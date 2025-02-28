package tech.shupi.mydata

import android.content.Intent
import android.os.Bundle
import com.nutomic.syncthingandroid.activities.FirstStartActivity
import com.nutomic.syncthingandroid.databinding.ActivityMain2Binding
import tech.shupi.mydata.base.BaseActivity

class MainActivity2 : BaseActivity() {

    private lateinit var binding: ActivityMain2Binding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        binding = ActivityMain2Binding.inflate(layoutInflater)
        setContentView(binding.root)

        initListener()
    }

    private fun initListener() {
        binding.mainFiles.setOnClickListener {
            val intent = Intent(this, FirstStartActivity::class.java)
            startActivity(intent)
        }
    }
}