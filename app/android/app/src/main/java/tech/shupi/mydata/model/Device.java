package tech.shupi.mydata.model;

import com.google.gson.annotations.SerializedName;

/**
 * 设备信息模型，对应Go代码中的Device结构体
 */
public class Device {
    @SerializedName("deviceID")
    private String deviceID;
    
    @SerializedName("name")
    private String name;
    
    @SerializedName("addresses")
    private String[] addresses;
    
    @SerializedName("compression")
    private String compression;
    
    @SerializedName("certName")
    private String certName;
    
    @SerializedName("introducer")
    private boolean introducer;
    
    @SerializedName("skipIntroductionRemovals")
    private boolean skipIntroductionRemovals;
    
    @SerializedName("introducedBy")
    private String introducedBy;
    
    @SerializedName("paused")
    private boolean paused;
    
    @SerializedName("allowedNetworks")
    private String[] allowedNetworks;
    
    @SerializedName("autoAcceptFolders")
    private boolean autoAcceptFolders;
    
    @SerializedName("maxSendKbps")
    private int maxSendKbps;
    
    @SerializedName("maxRecvKbps")
    private int maxRecvKbps;
    
    @SerializedName("ignoredFolders")
    private String[] ignoredFolders;
    
    @SerializedName("maxRequestKiB")
    private int maxRequestKiB;
    
    @SerializedName("untrusted")
    private boolean untrusted;
    
    @SerializedName("remoteGUIPort")
    private int remoteGUIPort;
    
    @SerializedName("numConnections")
    private int numConnections;
    
    // 新增字段，对应Go代码中的扩展字段
    @SerializedName("connected")
    private boolean connected;
    
    @SerializedName("connectionType")
    private String connectionType;
    
    @SerializedName("clientVersion")
    private String clientVersion;
    
    @SerializedName("inBytesTotal")
    private long inBytesTotal;
    
    @SerializedName("outBytesTotal")
    private long outBytesTotal;
    
    @SerializedName("isLocalNetwork")
    private boolean isLocalNetwork;
    
    @SerializedName("crypto")
    private String crypto;
    
    @SerializedName("lanAddresses")
    private String[] lanAddresses;
    
    // 构造函数
    public Device() {}
    
    // Getters and Setters
    public String getDeviceID() { return deviceID; }
    public void setDeviceID(String deviceID) { this.deviceID = deviceID; }
    
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    
    public String[] getAddresses() { return addresses; }
    public void setAddresses(String[] addresses) { this.addresses = addresses; }
    
    public String getCompression() { return compression; }
    public void setCompression(String compression) { this.compression = compression; }
    
    public String getCertName() { return certName; }
    public void setCertName(String certName) { this.certName = certName; }
    
    public boolean isIntroducer() { return introducer; }
    public void setIntroducer(boolean introducer) { this.introducer = introducer; }
    
    public boolean isSkipIntroductionRemovals() { return skipIntroductionRemovals; }
    public void setSkipIntroductionRemovals(boolean skipIntroductionRemovals) { this.skipIntroductionRemovals = skipIntroductionRemovals; }
    
    public String getIntroducedBy() { return introducedBy; }
    public void setIntroducedBy(String introducedBy) { this.introducedBy = introducedBy; }
    
    public boolean isPaused() { return paused; }
    public void setPaused(boolean paused) { this.paused = paused; }
    
    public String[] getAllowedNetworks() { return allowedNetworks; }
    public void setAllowedNetworks(String[] allowedNetworks) { this.allowedNetworks = allowedNetworks; }
    
    public boolean isAutoAcceptFolders() { return autoAcceptFolders; }
    public void setAutoAcceptFolders(boolean autoAcceptFolders) { this.autoAcceptFolders = autoAcceptFolders; }
    
    public int getMaxSendKbps() { return maxSendKbps; }
    public void setMaxSendKbps(int maxSendKbps) { this.maxSendKbps = maxSendKbps; }
    
    public int getMaxRecvKbps() { return maxRecvKbps; }
    public void setMaxRecvKbps(int maxRecvKbps) { this.maxRecvKbps = maxRecvKbps; }
    
    public String[] getIgnoredFolders() { return ignoredFolders; }
    public void setIgnoredFolders(String[] ignoredFolders) { this.ignoredFolders = ignoredFolders; }
    
    public int getMaxRequestKiB() { return maxRequestKiB; }
    public void setMaxRequestKiB(int maxRequestKiB) { this.maxRequestKiB = maxRequestKiB; }
    
    public boolean isUntrusted() { return untrusted; }
    public void setUntrusted(boolean untrusted) { this.untrusted = untrusted; }
    
    public int getRemoteGUIPort() { return remoteGUIPort; }
    public void setRemoteGUIPort(int remoteGUIPort) { this.remoteGUIPort = remoteGUIPort; }
    
    public int getNumConnections() { return numConnections; }
    public void setNumConnections(int numConnections) { this.numConnections = numConnections; }
    
    public boolean isConnected() { return connected; }
    public void setConnected(boolean connected) { this.connected = connected; }
    
    public String getConnectionType() { return connectionType; }
    public void setConnectionType(String connectionType) { this.connectionType = connectionType; }
    
    public String getClientVersion() { return clientVersion; }
    public void setClientVersion(String clientVersion) { this.clientVersion = clientVersion; }
    
    public long getInBytesTotal() { return inBytesTotal; }
    public void setInBytesTotal(long inBytesTotal) { this.inBytesTotal = inBytesTotal; }
    
    public long getOutBytesTotal() { return outBytesTotal; }
    public void setOutBytesTotal(long outBytesTotal) { this.outBytesTotal = outBytesTotal; }
    
    public boolean isLocalNetwork() { return isLocalNetwork; }
    public void setLocalNetwork(boolean isLocalNetwork) { this.isLocalNetwork = isLocalNetwork; }
    
    public String getCrypto() { return crypto; }
    public void setCrypto(String crypto) { this.crypto = crypto; }
    
    public String[] getLanAddresses() { return lanAddresses; }
    public void setLanAddresses(String[] lanAddresses) { this.lanAddresses = lanAddresses; }
}
