package main

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"runtime"
)

// App struct
type App struct {
	ctx context.Context
}

// Folder 结构体定义
type Folder struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Path  string `json:"path"`
}

// Device 结构体定义
type Device struct {
	DeviceID                 string   `json:"deviceID"`
	Name                     string   `json:"name"`
	Addresses                []string `json:"addresses"`
	Compression              string   `json:"compression"`
	CertName                 string   `json:"certName"`
	Introducer               bool     `json:"introducer"`
	SkipIntroductionRemovals bool     `json:"skipIntroductionRemovals"`
	IntroducedBy             string   `json:"introducedBy"`
	Paused                   bool     `json:"paused"`
	AllowedNetworks          []string `json:"allowedNetworks"`
	AutoAcceptFolders        bool     `json:"autoAcceptFolders"`
	MaxSendKbps              int      `json:"maxSendKbps"`
	MaxRecvKbps              int      `json:"maxRecvKbps"`
	IgnoredFolders           []string `json:"ignoredFolders"`
	MaxRequestKiB            int      `json:"maxRequestKiB"`
	Untrusted                bool     `json:"untrusted"`
	RemoteGUIPort            int      `json:"remoteGUIPort"`
	NumConnections           int      `json:"numConnections"`
}

type DevicesConfig struct {
	Devices []Device `json:"devices"`
}

const (
	syncthingAPI = "http://127.0.0.1:8384/rest/config" // Syncthing REST API 地址
	apiKey       = ""                                  // 替换为你的 Syncthing API Key
)

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// Greet returns a greeting for the given name
func (a *App) Greet(name string) string {
	return fmt.Sprintf("Hello %s, It's show time!", name)
}

// GetFolders 获取文件夹列表
func (a *App) GetFolders() ([]Folder, error) {
	resp, err := http.Get("http://localhost:8080/folders")
	if err != nil {
		return nil, fmt.Errorf("请求文件夹列表失败: %v", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取响应失败: %v", err)
	}

	var result struct {
		Code int      `json:"code"`
		Data []Folder `json:"data"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("解析响应失败: %v", err)
	}

	if result.Code != 0 {
		return nil, fmt.Errorf("获取文件夹列表失败: code=%d", result.Code)
	}

	return result.Data, nil
}

func getConfigPath() string {
	if runtime.GOOS == "android" {
		return "/data/data/com.nutomic.syncthingandroid/files/config.xml"
	}
	home, err := os.UserHomeDir()
	if err != nil {
		home = "~" // fallback
	}
	switch runtime.GOOS {
	case "windows":
		return home + `\\AppData\\Local\\Syncthing\\config.xml`
	case "darwin":
		return home + "/Library/Application Support/Syncthing/config.xml"
	default: // linux, etc.
		return home + "/.config/syncthing/config.xml"
	}
}

// 解析 config.xml 获取 apikey
func getApiKeyFromConfig() string {
	configPath := getConfigPath()
	type Gui struct {
		APIKey string `xml:"apikey"`
	}
	type Config struct {
		Gui Gui `xml:"gui"`
	}
	data, err := ioutil.ReadFile(configPath)
	if err != nil {
		return apiKey // 失败时用常量
	}
	var cfg Config
	err = xml.Unmarshal(data, &cfg)
	if err != nil || cfg.Gui.APIKey == "" {
		return apiKey
	}
	return cfg.Gui.APIKey
}

// GetDevices 返回所有设备列表
func (a *App) GetDevices() ([]Device, error) {
	req, err := http.NewRequest("GET", "http://127.0.0.1:8384/rest/config/devices", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("syncthing api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// 直接解析为设备数组
	var devices []Device
	if err := json.Unmarshal(body, &devices); err != nil {
		return nil, err
	}
	return devices, nil
}
