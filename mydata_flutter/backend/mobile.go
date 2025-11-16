package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sync"
)

// MobileAPI 提供供 Android 调用的 API
type MobileAPI struct {
	serverStarted bool
	serverMutex   sync.Mutex
	serverContext context.Context
	serverCancel  context.CancelFunc
}

var mobileAPI *MobileAPI
var mobileAPIOnce sync.Once

// GetMobileAPI 获取 MobileAPI 单例
func GetMobileAPI() *MobileAPI {
	mobileAPIOnce.Do(func() {
		mobileAPI = &MobileAPI{}
	})
	return mobileAPI
}

// StartServer 启动后端服务器
// 返回错误信息，如果成功则返回空字符串
func (m *MobileAPI) StartServer() string {
	m.serverMutex.Lock()
	defer m.serverMutex.Unlock()

	if m.serverStarted {
		return "服务器已经在运行"
	}

	// 创建上下文用于控制服务器生命周期
	m.serverContext, m.serverCancel = context.WithCancel(context.Background())

	// 在 goroutine 中启动服务器
	go func() {
		// 调用原有的 StartServer 函数
		// StartServer 会阻塞，所以需要在 goroutine 中运行
		StartServer()
		// 服务器停止后，更新状态
		m.serverMutex.Lock()
		m.serverStarted = false
		m.serverMutex.Unlock()
	}()

	m.serverStarted = true
	return ""
}

// StopServer 停止后端服务器
func (m *MobileAPI) StopServer() string {
	m.serverMutex.Lock()
	defer m.serverMutex.Unlock()

	if !m.serverStarted {
		return "服务器未运行"
	}

	if m.serverCancel != nil {
		m.serverCancel()
	}

	m.serverStarted = false
	return ""
}

// IsServerRunning 检查服务器是否正在运行
func (m *MobileAPI) IsServerRunning() bool {
	m.serverMutex.Lock()
	defer m.serverMutex.Unlock()
	return m.serverStarted
}

// GetServerURL 获取服务器 URL
func (m *MobileAPI) GetServerURL() string {
	return "https://localhost:8443"
}

// GetLocalDeviceID 获取本机设备 ID
func (m *MobileAPI) GetLocalDeviceID() (string, error) {
	return getLocalDeviceID()
}

// GetDevices 获取设备列表（JSON 字符串）
func (m *MobileAPI) GetDevices() (string, error) {
	devices, err := getDevicesFromSyncthing()
	if err != nil {
		return "", err
	}

	// 转换为 JSON
	jsonBytes, err := json.Marshal(devices)
	if err != nil {
		return "", fmt.Errorf("序列化设备列表失败: %v", err)
	}

	return string(jsonBytes), nil
}

// GetFolders 获取文件夹列表（JSON 字符串）
func (m *MobileAPI) GetFolders() (string, error) {
	mu.Lock()
	defer mu.Unlock()

	jsonBytes, err := json.Marshal(folders)
	if err != nil {
		return "", fmt.Errorf("序列化文件夹列表失败: %v", err)
	}

	return string(jsonBytes), nil
}

// StartSyncthing 启动 Syncthing 进程
func (m *MobileAPI) StartSyncthing() string {
	manager := GetSyncthingManager()
	if err := manager.Start(); err != nil {
		return fmt.Sprintf("启动 Syncthing 失败: %v", err)
	}
	return ""
}

// StopSyncthing 停止 Syncthing 进程
func (m *MobileAPI) StopSyncthing() string {
	manager := GetSyncthingManager()
	if err := manager.Stop(); err != nil {
		return fmt.Sprintf("停止 Syncthing 失败: %v", err)
	}
	return ""
}

// IsSyncthingRunning 检查 Syncthing 是否正在运行
func (m *MobileAPI) IsSyncthingRunning() bool {
	manager := GetSyncthingManager()
	return manager.IsRunning()
}

// SetSyncthingPath 设置 Syncthing 可执行文件路径（Android 平台使用）
// path: syncthing 二进制文件的完整路径，例如：/data/app/.../lib/arm64/libsyncthing.so
func (m *MobileAPI) SetSyncthingPath(path string) {
	manager := GetSyncthingManager()
	manager.SetExecutablePath(path)
}

// SetDataDir 设置数据目录路径（Android 平台使用）
// dataDir: 应用数据目录，例如：/data/user/0/tech.shupi.mydata/files
// 用于存储数据库、证书等文件
func (m *MobileAPI) SetDataDir(dataDir string) {
	// 设置全局数据目录（通过环境变量）
	os.Setenv("MYDATA_DATA_DIR", dataDir)

	// 更新 SyncthingManager 的路径（如果已经创建）
	manager := GetSyncthingManager()
	manager.SetDataPaths(dataDir, dataDir)
}

// SetLocalNetworkIPs 设置本机局域网 IP 地址（Android 平台使用）
// ips: 本机 IP 地址列表，例如：["192.168.1.100", "192.168.2.10"]
func (m *MobileAPI) SetLocalNetworkIPs(ips []string) {
	SetLocalNetworkIPs(ips)
}
