//go:build android
// +build android

package main

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/user"
	"path/filepath"
	"sync"

	"github.com/fsnotify/fsnotify"
	"gorm.io/gorm"
)

// 全局变量声明
var (
	db         *gorm.DB
	configPath string
	folders    []FolderEntry
	mu         sync.Mutex
)

// 结构体定义
type Folder struct {
	ID            string   `json:"id"`
	Label         string   `json:"label"`
	Path          string   `json:"path"`
	SharedDevices []string `json:"sharedDevices,omitempty"`
}

type SyncthingConfig struct {
	XMLName xml.Name      `xml:"configuration"`
	Folders []FolderEntry `xml:"folder"`
}

type FolderEntry struct {
	ID            string   `xml:"id,attr" json:"id"`
	Label         string   `xml:"label,attr" json:"label"`
	Path          string   `xml:"path,attr" json:"path"`
	SharedDevices []string `json:"sharedDevices,omitempty"`
}

type Device struct {
	DeviceID       string   `json:"deviceID"`
	Name           string   `json:"name"`
	Addresses      []string `json:"addresses"`
	Compression    string   `json:"compression"`
	CertName       string   `json:"certName"`
	Introducer     bool     `json:"introducer"`
	Connected      bool     `json:"connected"`
	ConnectionType string   `json:"connectionType"`
	ClientVersion  string   `json:"clientVersion"`
	InBytesTotal   int64    `json:"inBytesTotal"`
	OutBytesTotal  int64    `json:"outBytesTotal"`
	IsLocalNetwork bool     `json:"isLocalNetwork"`
	Crypto         string   `json:"crypto"`
}

type DevicesConfig struct {
	Devices []Device `json:"devices"`
}

type File struct {
	ID       uint   `gorm:"primaryKey" json:"id"`
	FolderID string `json:"folderId"`
	Path     string `json:"path"`
	Name     string `json:"name"`
	Size     int64  `json:"size"`
	ModTime  int64  `json:"modTime"`
	IsDir    bool   `json:"isDir"`
}

// 函数实现
func getConfigPath() string {
	usr, _ := user.Current()
	home := usr.HomeDir
	if home == "" {
		home = os.Getenv("HOME")
	}
	paths := []string{
		"/data/data/com.nutomic.syncthingandroid.debug/files/config.xml",                 // Android debug (优先)
		"/data/data/com.nutomic.syncthingandroid.debug/files/syncthing/config.xml",       // Android debug alternative
		"/data/data/com.nutomic.syncthingandroid/files/config.xml",                       // Android release
		"/data/data/com.nutomic.syncthingandroid/files/syncthing/config.xml",             // Android alternative
		filepath.Join(home, "AppData", "Local", "Syncthing", "config.xml"),               // Windows
		filepath.Join(home, "Library", "Application Support", "Syncthing", "config.xml"), // macOS
		filepath.Join(home, ".config", "syncthing", "config.xml"),                        // Linux/通用
		"config.xml", // fallback
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			fmt.Printf("找到配置文件: %s\n", p)
			return p
		}
	}
	fmt.Printf("未找到配置文件，使用默认路径: config.xml\n")
	return "config.xml"
}

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
		return "" // 失败时用空
	}
	var cfg Config
	err = xml.Unmarshal(data, &cfg)
	if err != nil || cfg.Gui.APIKey == "" {
		return ""
	}
	return cfg.Gui.APIKey
}

func loadAndIndex() {
	mu.Lock()
	defer mu.Unlock()

	fmt.Printf("=== 开始加载和索引 ===\n")

	// 从 Syncthing API 获取完整的文件夹配置
	syncthingFolders, err := loadFoldersFromSyncthing()
	if err != nil {
		log.Printf("从 Syncthing API 获取文件夹失败: %v，回退到 config.xml", err)
		// 回退到从 config.xml 加载
		loadFoldersFromConfig()
	} else {
		folders = syncthingFolders
		fmt.Printf("从 Syncthing API 获取到 %d 个同步文件夹:\n", len(folders))
		for _, folder := range folders {
			log.Printf("同步文件夹: [%s] %s (共享设备: %v)", folder.ID, folder.Path, folder.SharedDevices)
		}
	}

	// 清空旧索引
	fmt.Printf("清空旧索引...\n")
	if result := db.Session(&gorm.Session{AllowGlobalUpdate: true}).Delete(&File{}); result.Error != nil {
		fmt.Printf("清空旧索引失败: %v\n", result.Error)
	} else {
		fmt.Printf("清空旧索引成功，删除了 %d 条记录\n", result.RowsAffected)
	}

	// 遍历所有同步文件夹
	for _, folder := range folders {
		log.Printf("开始索引文件夹: [%s] %s", folder.ID, folder.Path)
		walkAndIndex(folder)
	}

	fmt.Printf("=== 加载和索引完成 ===\n")
}

// 从 Syncthing API 加载文件夹配置
func loadFoldersFromSyncthing() ([]FolderEntry, error) {
	// 构建 syncthing API URL
	syncthingURL := "http://127.0.0.1:8384/rest/config/folders"

	// 创建请求
	req, err := http.NewRequest("GET", syncthingURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %v", err)
	}

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request to syncthing: %v", err)
	}
	defer resp.Body.Close()

	// 检查响应状态
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return nil, fmt.Errorf("syncthing API returned status %d: %s", resp.StatusCode, string(body))
	}

	// 解析响应
	var syncthingFolders []map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&syncthingFolders); err != nil {
		return nil, fmt.Errorf("failed to decode response: %v", err)
	}

	// 转换为 FolderEntry 格式
	var folders []FolderEntry
	for _, sf := range syncthingFolders {
		folder := FolderEntry{
			ID:    getString(sf, "id"),
			Label: getString(sf, "label"),
			Path:  getString(sf, "path"),
		}

		// 提取共享设备信息
		if devices, ok := sf["devices"].([]interface{}); ok {
			for _, device := range devices {
				if deviceMap, ok := device.(map[string]interface{}); ok {
					if deviceID := getString(deviceMap, "deviceID"); deviceID != "" {
						folder.SharedDevices = append(folder.SharedDevices, deviceID)
					}
				}
			}
		}

		folders = append(folders, folder)
	}

	return folders, nil
}

// 从 config.xml 加载文件夹配置（回退方案）
func loadFoldersFromConfig() {
	// 解析 config.xml
	f, err := os.Open(configPath)
	if err != nil {
		log.Printf("无法打开 config.xml: %v, 路径: %s", err, configPath)
		return
	}
	defer f.Close()

	var cfg SyncthingConfig
	if err := xml.NewDecoder(f).Decode(&cfg); err != nil {
		log.Printf("解析 config.xml 失败: %v", err)
		return
	}

	folders = cfg.Folders
	fmt.Printf("从 config.xml 解析到 %d 个同步文件夹:\n", len(folders))
	for _, folder := range folders {
		log.Printf("同步文件夹: [%s] %s", folder.ID, folder.Path)
	}
}

// 辅助函数：安全地从 map 中获取字符串值
func getString(m map[string]interface{}, key string) string {
	if val, ok := m[key]; ok {
		if str, ok := val.(string); ok {
			return str
		}
	}
	return ""
}

func walkAndIndex(folder FolderEntry) {
	root := folder.Path
	fmt.Printf("开始索引文件夹: [%s] %s\n", folder.ID, root)

	fileCount := 0
	filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			fmt.Printf("跳过文件 %s (错误: %v)\n", path, err)
			return nil
		}

		// 计算相对路径
		rel, err := filepath.Rel(root, path)
		if err != nil {
			fmt.Printf("计算相对路径失败 %s: %v\n", path, err)
			return nil
		}

		if rel == "." {
			return nil
		}

		file := File{
			FolderID: folder.ID,
			Path:     rel,
			Name:     info.Name(),
			Size:     info.Size(),
			ModTime:  info.ModTime().Unix(),
			IsDir:    info.IsDir(),
		}

		if result := db.Create(&file); result.Error != nil {
			fmt.Printf("插入文件失败 %s: %v\n", rel, result.Error)
		} else {
			fileCount++
			if fileCount%100 == 0 {
				fmt.Printf("已索引 %d 个文件...\n", fileCount)
			}
		}
		return nil
	})

	fmt.Printf("文件夹 [%s] 索引完成，共 %d 个文件\n", folder.ID, fileCount)
}

func watchConfig() {
	// 监听 config.xml 变化，自动重新索引
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Printf("创建文件监听器失败: %v", err)
		return
	}
	defer watcher.Close()

	dir := filepath.Dir(configPath)
	if err := watcher.Add(dir); err != nil {
		log.Printf("监听目录失败: %v", err)
		return
	}

	for {
		select {
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			if event.Op&fsnotify.Write == fsnotify.Write && filepath.Base(event.Name) == filepath.Base(configPath) {
				log.Println("检测到 config.xml 变更，重新索引...")
				loadAndIndex()
			}
		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			log.Printf("文件监听错误: %v", err)
		}
	}
}
