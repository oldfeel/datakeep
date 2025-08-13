package tech.shupi.mydata.model;

import com.google.gson.annotations.SerializedName;

/**
 * 连接信息模型，对应Go代码中的ConnectionInfo结构体
 */
public class ConnectionInfo {
    @SerializedName("addresses")
    private String[] addresses;
    
    @SerializedName("connected")
    private boolean connected;
    
    @SerializedName("inBytesTotal")
    private long inBytesTotal;
    
    @SerializedName("outBytesTotal")
    private long outBytesTotal;
    
    @SerializedName("type")
    private String type;
    
    @SerializedName("address")
    private String address;
    
    @SerializedName("clientVersion")
    private String clientVersion;
    
    @SerializedName("isLocal")
    private boolean isLocal;
    
    @SerializedName("crypto")
    private String crypto;
    
    @SerializedName("primary")
    private PrimaryConnection primary;
    
    // 构造函数
    public ConnectionInfo() {}
    
    // Getters and Setters
    public String[] getAddresses() { return addresses; }
    public void setAddresses(String[] addresses) { this.addresses = addresses; }
    
    public boolean isConnected() { return connected; }
    public void setConnected(boolean connected) { this.connected = connected; }
    
    public long getInBytesTotal() { return inBytesTotal; }
    public void setInBytesTotal(long inBytesTotal) { this.inBytesTotal = inBytesTotal; }
    
    public long getOutBytesTotal() { return outBytesTotal; }
    public void setOutBytesTotal(long outBytesTotal) { this.outBytesTotal = outBytesTotal; }
    
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    
    public String getAddress() { return address; }
    public void setAddress(String address) { this.address = address; }
    
    public String getClientVersion() { return clientVersion; }
    public void setClientVersion(String clientVersion) { this.clientVersion = clientVersion; }
    
    public boolean isLocal() { return isLocal; }
    public void setLocal(boolean isLocal) { this.isLocal = isLocal; }
    
    public String getCrypto() { return crypto; }
    public void setCrypto(String crypto) { this.crypto = crypto; }
    
    public PrimaryConnection getPrimary() { return primary; }
    public void setPrimary(PrimaryConnection primary) { this.primary = primary; }
}
