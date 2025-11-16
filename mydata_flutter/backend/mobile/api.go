// Package mobile 提供供 Android/iOS 调用的 Go 绑定
package mobile

import (
	"fmt"
	"mydata_flutter/backend"
	"strings"
)

// API 提供供移动端调用的 API
type API struct{}

// NewAPI 创建新的 API 实例
func NewAPI() *API {
	return &API{}
}

// StartServer 启动后端服务器
// 返回错误信息，如果成功则返回空字符串
func (a *API) StartServer() string {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.StartServer()
}

// StopServer 停止后端服务器
func (a *API) StopServer() string {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.StopServer()
}

// IsServerRunning 检查服务器是否正在运行
func (a *API) IsServerRunning() bool {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.IsServerRunning()
}

// GetServerURL 获取服务器 URL
func (a *API) GetServerURL() string {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.GetServerURL()
}

// GetLocalDeviceID 获取本机设备 ID
func (a *API) GetLocalDeviceID() (string, error) {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.GetLocalDeviceID()
}

// GetDevices 获取设备列表（JSON 字符串）
func (a *API) GetDevices() (string, error) {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.GetDevices()
}

// GetFolders 获取文件夹列表（JSON 字符串）
func (a *API) GetFolders() (string, error) {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.GetFolders()
}

// StartSyncthing 启动 Syncthing 进程
func (a *API) StartSyncthing() string {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.StartSyncthing()
}

// StopSyncthing 停止 Syncthing 进程
func (a *API) StopSyncthing() string {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.StopSyncthing()
}

// IsSyncthingRunning 检查 Syncthing 是否正在运行
func (a *API) IsSyncthingRunning() bool {
	mobileAPI := backend.GetMobileAPI()
	return mobileAPI.IsSyncthingRunning()
}

// SetSyncthingPath 设置 Syncthing 可执行文件路径（Android 平台使用）
// path: syncthing 二进制文件的完整路径，例如：/data/app/.../lib/arm64/libsyncthing.so
func (a *API) SetSyncthingPath(path string) {
	mobileAPI := backend.GetMobileAPI()
	mobileAPI.SetSyncthingPath(path)
}

// SetDataDir 设置数据目录路径（Android 平台使用）
// dataDir: 应用数据目录，例如：/data/user/0/tech.shupi.mydata/files
func (a *API) SetDataDir(dataDir string) {
	mobileAPI := backend.GetMobileAPI()
	mobileAPI.SetDataDir(dataDir)
}

// SetLocalNetworkIPs 设置本机局域网 IP 地址（Android 平台使用）
// ips: 本机 IP 地址列表，用逗号分隔，例如："192.168.1.100,192.168.2.10"
func (a *API) SetLocalNetworkIPs(ips string) {
	mobileAPI := backend.GetMobileAPI()
	// 将逗号分隔的字符串转换为 []string
	var ipList []string
	if ips != "" {
		parts := strings.Split(ips, ",")
		for _, part := range parts {
			part = strings.TrimSpace(part)
			if part != "" {
				ipList = append(ipList, part)
			}
		}
	}
	mobileAPI.SetLocalNetworkIPs(ipList)
}

// Greetings 测试函数，用于验证绑定是否正常工作
func Greetings(name string) string {
	return fmt.Sprintf("Hello, %s! Go mobile binding is working.", name)
}
