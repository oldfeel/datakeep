//go:build !android
// +build !android

package main

import (
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/user"
	"path/filepath"
	"sync"

	"github.com/fsnotify/fsnotify"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

type Folder struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Path  string `json:"path"`
}

type SyncthingConfig struct {
	XMLName xml.Name      `xml:"configuration"`
	Folders []FolderEntry `xml:"folder"`
}

type FolderEntry struct {
	ID    string `xml:"id,attr" json:"id"`
	Label string `xml:"label,attr" json:"label"`
	Path  string `xml:"path,attr" json:"path"`
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
	IsLocal        bool     `json:"isLocal"`
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

const (
	syncthingAPI = "http://127.0.0.1:8384/rest/config" // Syncthing REST API 地址
	apiKey       = ""                                  // 替换为你的 Syncthing API Key
)

var (
	db         *gorm.DB
	configPath string
	folders    []FolderEntry
	mu         sync.Mutex
)

func getConfigPath() string {
	usr, _ := user.Current()
	home := usr.HomeDir
	if home == "" {
		home = os.Getenv("HOME")
	}
	paths := []string{
		"/data/data/com.nutomic.syncthingandroid/files/config.xml",                       // Android
		filepath.Join(home, "AppData", "Local", "Syncthing", "config.xml"),               // Windows
		filepath.Join(home, "Library", "Application Support", "Syncthing", "config.xml"), // macOS
		filepath.Join(home, ".config", "syncthing", "config.xml"),                        // Linux/通用
		"config.xml", // fallback
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return "config.xml"
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

func main() {
	var err error
	// 1. 初始化 GORM 数据库
	db, err = gorm.Open(sqlite.Open("files.db"), &gorm.Config{})
	if err != nil {
		log.Fatal("failed to connect database:", err)
	}
	if err := db.AutoMigrate(&File{}); err != nil {
		log.Fatal("auto migrate failed:", err)
	}

	// 2. 获取 config.xml 路径
	configPath = getConfigPath()
	fmt.Println("Syncthing config.xml:", configPath)

	// 3. 准备索引
	fmt.Println("准备索引")
	loadAndIndex()
	fmt.Println("索引完成")

	// 4. 监听 config.xml 变化
	go watchConfig()

	// 5. 启动 Fiber API 服务
	app := fiber.New()
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowHeaders: "*",
		AllowMethods: "GET,POST,OPTIONS",
	}))
	app.Get("/api/folder/:folderId", folderFilesHandler)
	app.Get("/api/devices", devicesHandler)
	app.Get("/api/device/:deviceId/folders", deviceFoldersHandler)
	go func() {
		if err := app.Listen(":8080"); err != nil {
			log.Fatal(err)
		}
	}()

	select {}
}

func loadAndIndex() {
	mu.Lock()
	defer mu.Unlock()

	fmt.Printf("=== 开始加载和索引 ===\n")

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
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Println("fsnotify 初始化失败:", err)
		return
	}
	defer watcher.Close()
	watcher.Add(configPath)
	for {
		select {
		case event := <-watcher.Events:
			if event.Op&fsnotify.Write == fsnotify.Write {
				fmt.Println("检测到 config.xml 变更，重新加载...")
				loadAndIndex()
			}
		case err := <-watcher.Errors:
			log.Println("fsnotify 错误:", err)
		}
	}
}
