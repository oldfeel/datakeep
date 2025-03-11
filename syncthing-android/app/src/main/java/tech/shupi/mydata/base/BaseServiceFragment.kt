package tech.shupi.mydata.base

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.fragment.app.Fragment
import com.nutomic.syncthingandroid.R
import com.nutomic.syncthingandroid.service.SyncthingService.OnServiceStateChangeListener

abstract class BaseServiceFragment : BaseFragment(), OnServiceStateChangeListener {
}