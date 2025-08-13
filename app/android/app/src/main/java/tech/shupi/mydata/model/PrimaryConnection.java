package tech.shupi.mydata.model;

import com.google.gson.annotations.SerializedName;

/**
 * 主要连接信息
 */
public class PrimaryConnection {
    @SerializedName("address")
    private String address;
    
    @SerializedName("type")
    private String type;
    
    // 构造函数
    public PrimaryConnection() {}
    
    // Getters and Setters
    public String getAddress() { return address; }
    public void setAddress(String address) { this.address = address; }
    
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
}
