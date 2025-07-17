package tech.shuipi.syncthing.service

import android.os.Binder

/**
 * 服务绑定器，用于 Activity 和服务之间的通信
 */
class SyncthingServiceBinder(private val service: SyncthingService) : Binder() {
    
    fun getService(): SyncthingService {
        return service
    }
} 