//go:build !android
// +build !android

package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
	"os/user"
	"path/filepath"
	"sync"
	"time"

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
	Hash     string `json:"hash"`  // 文件内容的哈希值
	Perms    uint32 `json:"perms"` // 文件权限
}

// 文件映射结构，用于快速查找
type FileMap map[string]*File

// 文件变化类型
type ChangeType int

const (
	ChangeNone ChangeType = iota
	ChangeNew
	ChangeModified
	ChangeDeleted
)

// 文件变化记录
type FileChange struct {
	Type    ChangeType
	File    *File
	OldFile *File
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
	// 添加命令行参数
	forceReindex = flag.Bool("force", false, "强制重新索引所有文件")
	// 添加索引状态管理
	indexingStatus = struct {
		sync.RWMutex
		isIndexing bool
		progress   string
		startTime  time.Time
		endTime    time.Time
		error      error
	}{}
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
	// 解析命令行参数
	flag.Parse()

	// 显示帮助信息
	if len(os.Args) > 1 && (os.Args[1] == "-h" || os.Args[1] == "--help") {
		fmt.Println("Syncthing 文件索引服务")
		fmt.Println("用法: ./api [选项]")
		fmt.Println("选项:")
		flag.PrintDefaults()
		fmt.Println("\n示例:")
		fmt.Println("  ./api              # 增量索引模式（默认）")
		fmt.Println("  ./api -force       # 强制重新索引所有文件")
		return
	}

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

	// 3. 异步启动索引
	fmt.Println("启动异步索引...")
	go func() {
		if *forceReindex {
			fmt.Println("强制重新索引模式")
			asyncForceReindexAll()
		} else {
			fmt.Println("增量索引模式")
			asyncLoadAndIndex()
		}
	}()

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
	// 添加索引状态查询接口
	app.Get("/api/index/status", indexStatusHandler)

	fmt.Println("API 服务启动在 :8080")
	if err := app.Listen(":8080"); err != nil {
		log.Fatal(err)
	}
}

// 异步索引状态处理器
func indexStatusHandler(c *fiber.Ctx) error {
	indexingStatus.RLock()
	defer indexingStatus.RUnlock()

	status := map[string]interface{}{
		"isIndexing": indexingStatus.isIndexing,
		"progress":   indexingStatus.progress,
		"startTime":  indexingStatus.startTime,
		"endTime":    indexingStatus.endTime,
	}

	if indexingStatus.error != nil {
		status["error"] = indexingStatus.error.Error()
	}

	return c.JSON(status)
}

// 异步索引主函数
func asyncLoadAndIndex() {
	// 设置索引状态
	indexingStatus.Lock()
	indexingStatus.isIndexing = true
	indexingStatus.progress = "开始增量索引"
	indexingStatus.startTime = time.Now()
	indexingStatus.error = nil
	indexingStatus.Unlock()

	defer func() {
		indexingStatus.Lock()
		indexingStatus.isIndexing = false
		indexingStatus.endTime = time.Now()
		indexingStatus.Unlock()
	}()

	mu.Lock()
	defer mu.Unlock()

	indexingStatus.Lock()
	indexingStatus.progress = "解析配置文件"
	indexingStatus.Unlock()

	fmt.Printf("=== 开始异步增量索引 ===\n")

	// 解析 config.xml
	f, err := os.Open(configPath)
	if err != nil {
		indexingStatus.Lock()
		indexingStatus.error = err
		indexingStatus.Unlock()
		log.Printf("无法打开 config.xml: %v, 路径: %s", err, configPath)
		return
	}
	defer f.Close()

	var cfg SyncthingConfig
	if err := xml.NewDecoder(f).Decode(&cfg); err != nil {
		indexingStatus.Lock()
		indexingStatus.error = err
		indexingStatus.Unlock()
		log.Printf("解析 config.xml 失败: %v", err)
		return
	}

	folders = cfg.Folders
	fmt.Printf("从 config.xml 解析到 %d 个同步文件夹:\n", len(folders))
	for _, folder := range folders {
		log.Printf("同步文件夹: [%s] %s", folder.ID, folder.Path)
	}

	// 遍历所有同步文件夹进行增量索引
	for i, folder := range folders {
		indexingStatus.Lock()
		indexingStatus.progress = fmt.Sprintf("索引文件夹 %d/%d: %s", i+1, len(folders), folder.ID)
		indexingStatus.Unlock()

		log.Printf("开始增量索引文件夹: [%s] %s", folder.ID, folder.Path)
		asyncIncrementalIndex(folder)
	}

	indexingStatus.Lock()
	indexingStatus.progress = "索引完成"
	indexingStatus.Unlock()

	fmt.Printf("=== 异步增量索引完成 ===\n")
}

// 异步增量索引主函数
func asyncIncrementalIndex(folder FolderEntry) {
	root := folder.Path
	fmt.Printf("开始增量索引文件夹: [%s] %s\n", folder.ID, root)

	// 1. 获取数据库中现有的文件映射
	indexingStatus.Lock()
	indexingStatus.progress = fmt.Sprintf("获取现有文件: %s", folder.ID)
	indexingStatus.Unlock()

	existingFiles, err := getExistingFiles(folder.ID)
	if err != nil {
		log.Printf("获取现有文件失败: %v", err)
		return
	}
	fmt.Printf("数据库中现有 %d 个文件\n", len(existingFiles))

	// 2. 扫描文件系统获取当前文件
	indexingStatus.Lock()
	indexingStatus.progress = fmt.Sprintf("扫描文件系统: %s", folder.ID)
	indexingStatus.Unlock()

	currentFiles, err := scanFileSystem(folder)
	if err != nil {
		log.Printf("扫描文件系统失败: %v", err)
		return
	}
	fmt.Printf("文件系统中发现 %d 个文件\n", len(currentFiles))

	// 3. 比较差异并生成变化列表
	indexingStatus.Lock()
	indexingStatus.progress = fmt.Sprintf("比较文件差异: %s", folder.ID)
	indexingStatus.Unlock()

	changes := compareFiles(existingFiles, currentFiles)
	fmt.Printf("检测到 %d 个文件变化\n", len(changes))

	// 4. 批量处理变化
	indexingStatus.Lock()
	indexingStatus.progress = fmt.Sprintf("处理文件变化: %s (%d 个变化)", folder.ID, len(changes))
	indexingStatus.Unlock()

	if err := processChanges(changes, folder.ID); err != nil {
		log.Printf("处理文件变化失败: %v", err)
		return
	}

	fmt.Printf("文件夹 [%s] 增量索引完成\n", folder.ID)
}

// 异步强制重新索引
func asyncForceReindexAll() {
	// 设置索引状态
	indexingStatus.Lock()
	indexingStatus.isIndexing = true
	indexingStatus.progress = "开始强制重新索引"
	indexingStatus.startTime = time.Now()
	indexingStatus.error = nil
	indexingStatus.Unlock()

	defer func() {
		indexingStatus.Lock()
		indexingStatus.isIndexing = false
		indexingStatus.endTime = time.Now()
		indexingStatus.Unlock()
	}()

	mu.Lock()
	defer mu.Unlock()

	fmt.Printf("=== 开始异步强制重新索引 ===\n")

	// 解析 config.xml
	f, err := os.Open(configPath)
	if err != nil {
		indexingStatus.Lock()
		indexingStatus.error = err
		indexingStatus.Unlock()
		log.Printf("无法打开 config.xml: %v, 路径: %s", err, configPath)
		return
	}
	defer f.Close()

	var cfg SyncthingConfig
	if err := xml.NewDecoder(f).Decode(&cfg); err != nil {
		indexingStatus.Lock()
		indexingStatus.error = err
		indexingStatus.Unlock()
		log.Printf("解析 config.xml 失败: %v", err)
		return
	}

	folders = cfg.Folders
	fmt.Printf("从 config.xml 解析到 %d 个同步文件夹:\n", len(folders))
	for _, folder := range folders {
		log.Printf("同步文件夹: [%s] %s", folder.ID, folder.Path)
	}

	// 清空旧索引
	indexingStatus.Lock()
	indexingStatus.progress = "清空旧索引"
	indexingStatus.Unlock()

	fmt.Printf("清空旧索引...\n")
	if result := db.Session(&gorm.Session{AllowGlobalUpdate: true}).Delete(&File{}); result.Error != nil {
		fmt.Printf("清空旧索引失败: %v\n", result.Error)
	} else {
		fmt.Printf("清空旧索引成功，删除了 %d 条记录\n", result.RowsAffected)
	}

	// 遍历所有同步文件夹
	for i, folder := range folders {
		indexingStatus.Lock()
		indexingStatus.progress = fmt.Sprintf("强制索引文件夹 %d/%d: %s", i+1, len(folders), folder.ID)
		indexingStatus.Unlock()

		log.Printf("开始索引文件夹: [%s] %s", folder.ID, folder.Path)
		asyncWalkAndIndex(folder)
	}

	indexingStatus.Lock()
	indexingStatus.progress = "强制重新索引完成"
	indexingStatus.Unlock()

	fmt.Printf("=== 异步强制重新索引完成 ===\n")
}

// 异步文件系统遍历和索引
func asyncWalkAndIndex(folder FolderEntry) {
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

		// 计算文件哈希（仅对文件计算，目录跳过）
		var hash string
		if !info.IsDir() {
			hash, err = calculateFileHash(path)
			if err != nil {
				fmt.Printf("计算文件哈希失败 %s: %v\n", path, err)
				// 继续处理，使用空哈希
			}
		}

		file := File{
			FolderID: folder.ID,
			Path:     rel,
			Name:     info.Name(),
			Size:     info.Size(),
			ModTime:  info.ModTime().Unix(),
			IsDir:    info.IsDir(),
			Hash:     hash,
			Perms:    uint32(info.Mode() & os.ModePerm),
		}

		if result := db.Create(&file); result.Error != nil {
			fmt.Printf("插入文件失败 %s: %v\n", rel, result.Error)
		} else {
			fileCount++
			if fileCount%100 == 0 {
				indexingStatus.Lock()
				indexingStatus.progress = fmt.Sprintf("索引进度: %s - %d 个文件", folder.ID, fileCount)
				indexingStatus.Unlock()
				fmt.Printf("已索引 %d 个文件...\n", fileCount)
			}
		}
		return nil
	})

	fmt.Printf("文件夹 [%s] 索引完成，共 %d 个文件\n", folder.ID, fileCount)
}

// 修改文件变化监听为异步
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
				fmt.Println("检测到 config.xml 变更，异步重新加载...")
				// 异步重新索引
				go func() {
					if *forceReindex {
						asyncForceReindexAll()
					} else {
						asyncLoadAndIndex()
					}
				}()
			}
		case err := <-watcher.Errors:
			log.Println("fsnotify 错误:", err)
		}
	}
}

// 保持原有的同步函数用于向后兼容
func loadAndIndex() {
	asyncLoadAndIndex()
}

func forceReindexAll() {
	asyncForceReindexAll()
}

func walkAndIndex(folder FolderEntry) {
	asyncWalkAndIndex(folder)
}

func incrementalIndex(folder FolderEntry) {
	asyncIncrementalIndex(folder)
}

// 获取数据库中现有的文件映射
func getExistingFiles(folderID string) (FileMap, error) {
	var files []File
	if err := db.Where("folder_id = ?", folderID).Find(&files).Error; err != nil {
		return nil, err
	}

	fileMap := make(FileMap)
	for i := range files {
		fileMap[files[i].Path] = &files[i]
	}
	return fileMap, nil
}

// 计算文件哈希
func calculateFileHash(filePath string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer file.Close()

	// 使用缓冲区提高性能
	buf := make([]byte, 32*1024) // 32KB 缓冲区
	hash := sha256.New()

	_, err = io.CopyBuffer(hash, file, buf)
	if err != nil {
		return "", err
	}

	return hex.EncodeToString(hash.Sum(nil)), nil
}

// 扫描文件系统获取当前文件（优化版本）
func scanFileSystem(folder FolderEntry) (FileMap, error) {
	fileMap := make(FileMap)
	root := folder.Path
	fileCount := 0
	hashCount := 0

	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
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

		// 计算文件哈希（仅对文件计算，目录跳过）
		var hash string
		if !info.IsDir() {
			hash, err = calculateFileHash(path)
			if err != nil {
				fmt.Printf("计算文件哈希失败 %s: %v\n", path, err)
				// 继续处理，使用空哈希
			} else {
				hashCount++
			}
		}

		file := &File{
			FolderID: folder.ID,
			Path:     rel,
			Name:     info.Name(),
			Size:     info.Size(),
			ModTime:  info.ModTime().Unix(),
			IsDir:    info.IsDir(),
			Hash:     hash,
			Perms:    uint32(info.Mode() & os.ModePerm),
		}

		fileMap[rel] = file
		fileCount++

		// 显示进度
		if fileCount%100 == 0 {
			fmt.Printf("已扫描 %d 个文件，计算了 %d 个哈希...\n", fileCount, hashCount)
		}

		return nil
	})

	if err == nil {
		fmt.Printf("扫描完成：共 %d 个文件，计算了 %d 个哈希\n", fileCount, hashCount)
	}

	return fileMap, err
}

// 比较文件差异
func compareFiles(existing, current FileMap) []FileChange {
	var changes []FileChange

	// 检查新增和修改的文件
	for path, currentFile := range current {
		if existingFile, exists := existing[path]; exists {
			// 文件存在，检查是否变化
			if filesEqual(existingFile, currentFile) {
				// 文件未变化，跳过
				continue
			}
			// 文件被修改
			changes = append(changes, FileChange{
				Type:    ChangeModified,
				File:    currentFile,
				OldFile: existingFile,
			})
		} else {
			// 新文件
			changes = append(changes, FileChange{
				Type: ChangeNew,
				File: currentFile,
			})
		}
	}

	// 检查删除的文件
	for path, existingFile := range existing {
		if _, exists := current[path]; !exists {
			// 文件被删除
			changes = append(changes, FileChange{
				Type:    ChangeDeleted,
				OldFile: existingFile,
			})
		}
	}

	return changes
}

// 比较两个文件是否相等
func filesEqual(f1, f2 *File) bool {
	// 基本属性比较
	if f1.Size != f2.Size || f1.ModTime != f2.ModTime || f1.IsDir != f2.IsDir {
		return false
	}

	// 如果是文件，比较哈希值
	if !f1.IsDir && f1.Hash != "" && f2.Hash != "" {
		return f1.Hash == f2.Hash
	}

	// 如果哈希值不可用，比较修改时间（允许1秒的误差）
	if abs(f1.ModTime-f2.ModTime) <= 1 {
		return true
	}

	return false
}

// 绝对值函数
func abs(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}

// 批量处理文件变化
func processChanges(changes []FileChange, folderID string) error {
	if len(changes) == 0 {
		return nil
	}

	// 使用事务批量处理
	tx := db.Begin()
	if tx.Error != nil {
		return tx.Error
	}
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	var newFiles []File
	var updateFiles []File
	var deleteIDs []uint

	for _, change := range changes {
		switch change.Type {
		case ChangeNew:
			newFiles = append(newFiles, *change.File)
		case ChangeModified:
			// 更新现有文件
			updateFile := *change.File
			updateFile.ID = change.OldFile.ID
			updateFiles = append(updateFiles, updateFile)
		case ChangeDeleted:
			deleteIDs = append(deleteIDs, change.OldFile.ID)
		}
	}

	// 批量插入新文件
	if len(newFiles) > 0 {
		if err := tx.Create(&newFiles).Error; err != nil {
			tx.Rollback()
			return err
		}
		fmt.Printf("插入 %d 个新文件\n", len(newFiles))
	}

	// 批量更新修改的文件
	for _, file := range updateFiles {
		if err := tx.Save(&file).Error; err != nil {
			tx.Rollback()
			return err
		}
	}
	if len(updateFiles) > 0 {
		fmt.Printf("更新 %d 个文件\n", len(updateFiles))
	}

	// 批量删除文件
	if len(deleteIDs) > 0 {
		if err := tx.Delete(&File{}, deleteIDs).Error; err != nil {
			tx.Rollback()
			return err
		}
		fmt.Printf("删除 %d 个文件\n", len(deleteIDs))
	}

	return tx.Commit().Error
}
