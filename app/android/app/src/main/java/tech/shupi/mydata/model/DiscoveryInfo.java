package tech.shupi.mydata.model;

import com.google.gson.annotations.SerializedName;

/**
 * 发现信息模型，对应Go代码中的DiscoveryInfo结构体
 */
public class DiscoveryInfo {
    @SerializedName("addresses")
    private String[] addresses;
    
    // 构造函数
    public DiscoveryInfo() {}
    
    // Getters and Setters
    public String[] getAddresses() { return addresses; }
    public void setAddresses(String[] addresses) { this.addresses = addresses; }
}
