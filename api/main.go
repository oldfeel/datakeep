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
	DeviceID    string   `json:"deviceID"`
	Name        string   `json:"name"`
	Addresses   []string `json:"addresses"`
	Compression string   `json:"compression"`
	CertName    string   `json:"certName"`
	Introducer  bool     `json:"introducer"`
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
		"/data/data/com.nutomic.syncthingandroid/files/config.xml",              // Android
		filepath.Join(home, "AppData/Local/Syncthing/config.xml"),               // Windows
		filepath.Join(home, "Library/Application Support/Syncthing/config.xml"), // macOS
		filepath.Join(home, ".config/syncthing/config.xml"),                     // Linux/通用
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

func getDevicesFromSyncthing() ([]Device, error) {
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

	var devices []Device
	if err := json.Unmarshal(body, &devices); err != nil {
		return nil, err
	}
	return devices, nil
}

func success(c *fiber.Ctx, data interface{}) error {
	return c.JSON(fiber.Map{
		"code": 0,
		"data": data,
	})
}

func fail(c *fiber.Ctx, code int, msg string) error {
	return c.JSON(fiber.Map{
		"code": code,
		"data": msg,
	})
}

// /files?path=/storage/emulated/0/Syncthing
func filesHandler(c *fiber.Ctx) error {
	path := c.Query("path")
	if path == "" {
		return fail(c, 1002, "Missing path param")
	}
	files, err := ioutil.ReadDir(path)
	if err != nil {
		return fail(c, 1003, "Failed to read dir: "+err.Error())
	}
	var result []fiber.Map
	for _, f := range files {
		result = append(result, fiber.Map{
			"name":    f.Name(),
			"isDir":   f.IsDir(),
			"size":    f.Size(),
			"modTime": f.ModTime(),
			"absPath": filepath.Join(path, f.Name()),
		})
	}
	return success(c, result)
}

func devicesHandler(c *fiber.Ctx) error {
	devices, err := getDevicesFromSyncthing()
	if err != nil {
		return fail(c, 1004, "Failed to get devices: "+err.Error())
	}
	return success(c, devices)
}

func deviceFoldersHandler(c *fiber.Ctx) error {
	// 目前只返回本机 config.xml 里的所有同步文件夹
	return success(c, folders)
}

func folderFilesHandler(c *fiber.Ctx) error {
	folderId := c.Params("folderId")
	path := c.Query("path", "")
	var files []File
	var err error
	if path == "" {
		// 根目录：path 不包含 '/'
		err = db.Where("folder_id = ? AND path NOT LIKE ?", folderId, "%/%").Find(&files).Error
	} else {
		// 子目录：path = "a/b"，只查 a/b/xxx（不递归）
		prefix := path + "/"
		// 只查 path 下一级（不含更深层）
		err = db.Where("folder_id = ? AND path LIKE ? AND path NOT LIKE ?", folderId, prefix+"%", prefix+"%/%/%").Find(&files).Error
	}
	if err != nil {
		return fail(c, 1005, "数据库查询失败: "+err.Error())
	}
	return success(c, files)
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

	// 阻塞主线程
	select {}
}

func loadAndIndex() {
	mu.Lock()
	defer mu.Unlock()
	// 解析 config.xml
	f, err := os.Open(configPath)
	if err != nil {
		log.Println("无法打开 config.xml:", err)
		return
	}
	defer f.Close()
	var cfg SyncthingConfig
	if err := xml.NewDecoder(f).Decode(&cfg); err != nil {
		log.Println("解析 config.xml 失败:", err)
		return
	}
	folders = cfg.Folders
	fmt.Println("已获取同步文件夹:")
	for _, folder := range folders {
		fmt.Printf("- [%s] %s\n", folder.ID, folder.Path)
	}
	// 清空旧索引
	db.Session(&gorm.Session{AllowGlobalUpdate: true}).Delete(&File{})
	// 遍历所有同步文件夹
	for _, folder := range folders {
		walkAndIndex(folder)
	}
}

func walkAndIndex(folder FolderEntry) {
	root := folder.Path
	filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
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
		db.Create(&file)
		return nil
	})
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
