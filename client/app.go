package main

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
	"os"
	goruntime "runtime"

	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
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

type SharedFolder struct {
	Folder
	DeviceID string `json:"deviceID"`
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

type SyncthingConfig struct {
	Folders []Folder `json:"folders"`
}

// Block 结构体定义文件块信息
type Block struct {
	Hash   string `json:"hash"`
	Offset int64  `json:"offset"`
	Size   int    `json:"size"`
}

// File 结构体定义文件信息
type File struct {
	Name          string  `json:"name"`
	Type          string  `json:"type"`
	Size          int64   `json:"size"`
	Modified      string  `json:"modified"`
	Version       string  `json:"version"`
	LocalFlags    int     `json:"localFlags"`
	Permissions   string  `json:"permissions"`
	Deleted       bool    `json:"deleted"`
	Invalid       bool    `json:"invalid"`
	IgnoreDelete  bool    `json:"ignoreDelete"`
	NoPermissions bool    `json:"noPermissions"`
	Sequence      int64   `json:"sequence"`
	ModTimeBy     string  `json:"modTimeBy"`
	BlockSize     int     `json:"blockSize"`
	SymlinkTarget string  `json:"symlinkTarget"`
	Blocks        []Block `json:"blocks"`
}

// FolderContents 结构体定义文件夹内容
type FolderContents struct {
	Files []File `json:"files"`
}

const (
	syncthingAPI = "http://127.0.0.1:8384" // Syncthing REST API 地址
	apiKey       = ""                      // 替换为你的 Syncthing API Key
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

// GetFolders 返回所有文件夹列表
func (a *App) GetFolders() ([]Folder, error) {
	req, err := http.NewRequest("GET", "http://127.0.0.1:8384/rest/config/folders", nil)
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

	// 直接解析为文件夹数组
	var folders []Folder
	if err := json.Unmarshal(body, &folders); err != nil {
		return nil, err
	}
	return folders, nil
}

func getConfigPath() string {
	if goruntime.GOOS == "android" {
		return "/data/data/com.nutomic.syncthingandroid/files/config.xml"
	}
	home, err := os.UserHomeDir()
	if err != nil {
		home = "~" // fallback
	}
	switch goruntime.GOOS {
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

// GetDeviceFolders 返回指定设备的文件夹列表
func (a *App) GetDeviceFolders(deviceID string) ([]Folder, error) {
	if deviceID == "local" {
		// 获取本机文件夹列表
		return a.GetFolders()
	}

	// 获取设备共享的文件夹列表
	req, err := http.NewRequest("GET", fmt.Sprintf("http://127.0.0.1:8384/rest/config/folders?device=%s", deviceID), nil)
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

	// 解析为文件夹数组
	var folders []Folder
	if err := json.Unmarshal(body, &folders); err != nil {
		return nil, err
	}
	return folders, nil
}

// GetFolderContents 获取指定文件夹的内容，支持 path 参数
func (a *App) GetFolderContents(folderId string, path string) ([]File, error) {
	apiUrl := fmt.Sprintf("%s/rest/db/browse?folder=%s", syncthingAPI, folderId)
	if path != "" {
		apiUrl += "&path=" + url.QueryEscape(path)
	}
	fmt.Printf("请求 Syncthing browse API: %s (原始 path: %s)\n", apiUrl, path)
	req, err := http.NewRequest("GET", apiUrl, nil)
	if err != nil {
		return nil, fmt.Errorf("创建请求失败: %v", err)
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("获取文件夹内容失败: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API 请求失败，状态码: %d", resp.StatusCode)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取响应失败: %v", err)
	}

	var contents []File
	if err := json.Unmarshal(body, &contents); err != nil {
		var folderContents FolderContents
		if err := json.Unmarshal(body, &folderContents); err != nil {
			return nil, fmt.Errorf("解析响应失败: %v", err)
		}
		contents = folderContents.Files
	}

	return contents, nil
}

// SelectFolder 打开文件夹选择对话框并返回选择的文件夹路径
func (a *App) SelectFolder() (string, error) {
	selectedPath, err := wailsruntime.OpenDirectoryDialog(a.ctx, wailsruntime.OpenDialogOptions{
		Title: "选择要同步的文件夹",
	})
	if err != nil {
		return "", fmt.Errorf("选择文件夹失败: %v", err)
	}
	return selectedPath, nil
}
