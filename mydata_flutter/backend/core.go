package backend

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
	"go.uber.org/zap"
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
	FolderID string `gorm:"column:folder_id" json:"folderId"`
	Path     string `json:"path"`
	Name     string `json:"name"`
	Size     int64  `json:"size"`
	ModTime  int64  `json:"modTime"`
	IsDir    bool   `json:"isDir"`
}

// 设备表
// 保存设备 id、name、局域网 ip
// 表名: devices
type DeviceInfo struct {
	ID       uint   `gorm:"primaryKey" json:"id"`                 // 自增主键
	DeviceID string `gorm:"uniqueIndex;not null" json:"deviceId"` // 设备唯一ID
	Name     string `json:"name"`                                 // 设备名称
	LanIP    string `json:"lanIp"`                                // 局域网IP
}

// 文件夹表
// 保存设备id、文件夹名字、文件夹id、文件夹路径
// 表名: folders
type FolderInfo struct {
	ID       uint   `gorm:"primaryKey" json:"id"`           // 自增主键
	DeviceID string `gorm:"index;not null" json:"deviceId"` // 所属设备ID
	FolderID string `gorm:"not null" json:"folderId"`       // 文件夹唯一ID
	Name     string `json:"name"`                           // 文件夹名字
	Path     string `json:"path"`                           // 文件夹路径
}

// fileExists 检查文件是否存在（用于配置文件路径查找）
func fileExists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

// getConfigPath 使用与 Syncthing 相同的逻辑查找配置文件路径
// getSyncthingHomeFromProcess 从运行的 Syncthing 进程获取 -home 参数
func getSyncthingHomeFromProcess() string {
	logger.Info("尝试从运行的 Syncthing 进程获取 -home 参数...")

	// 查找 syncthing 进程（可能有多个，取第一个）
	cmd := exec.Command("pgrep", "-f", "syncthing.*-home")
	output, err := cmd.Output()
	if err != nil {
		logger.Info("未找到运行中的 Syncthing 进程（带 -home 参数）", zap.Error(err))
		return ""
	}

	// 解析进程 ID（pgrep 可能返回多个 PID，用换行符分隔）
	pidLines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(pidLines) == 0 || pidLines[0] == "" {
		logger.Info("未找到 Syncthing 进程 ID")
		return ""
	}
	logger.Info("找到 Syncthing 进程", zap.Int("totalPids", len(pidLines)), zap.Strings("pids", pidLines))

	// 遍历所有进程 ID，尝试读取命令行参数（因为有些进程可能已经结束）
	for _, pid := range pidLines {
		pid = strings.TrimSpace(pid)
		if pid == "" {
			continue
		}

		logger.Info("尝试读取进程命令行参数", zap.String("pid", pid))

		// 读取进程的命令行参数
		cmdlinePath := filepath.Join("/proc", pid, "cmdline")
		cmdlineData, err := ioutil.ReadFile(cmdlinePath)
		if err != nil {
			logger.Warn("无法读取进程命令行参数", zap.String("pid", pid), zap.String("path", cmdlinePath), zap.Error(err))
			continue // 尝试下一个进程
		}

		// cmdline 文件使用 \0 分隔参数
		args := strings.Split(string(cmdlineData), "\x00")
		logger.Info("Syncthing 进程命令行参数", zap.String("pid", pid), zap.Any("args", args))

		// 查找 -home 参数
		for i, arg := range args {
			if arg == "-home" && i+1 < len(args) {
				homePath := args[i+1]
				logger.Info("找到 -home 参数", zap.String("pid", pid), zap.String("path", homePath))

				// 确保路径是绝对路径
				if filepath.IsAbs(homePath) {
					logger.Info("使用绝对路径", zap.String("path", homePath))
					return homePath
				}
				// 如果是相对路径，尝试转换为绝对路径
				if absPath, err := filepath.Abs(homePath); err == nil {
					logger.Info("将相对路径转换为绝对路径", zap.String("original", homePath), zap.String("absolute", absPath))
					return absPath
				}
				logger.Warn("无法转换相对路径为绝对路径", zap.String("path", homePath))
				return homePath
			}
		}

		logger.Info("进程参数中未找到 -home", zap.String("pid", pid))
	}

	logger.Info("所有进程参数中都未找到 -home")
	return ""
}

// 参考: syncthing/lib/locations/locations.go 的 unixConfigDir 函数
func getConfigPath() string {
	// 如果已经找到过配置路径，验证它是否存在
	// 注意：不使用锁，因为可能被持有锁的函数调用，会导致死锁
	if configPath != "" {
		// 验证配置文件是否存在
		if _, err := os.Stat(configPath); err == nil {
			return configPath
		}
		// 如果配置文件不存在，清空 configPath 重新查找
		configPath = ""
	}

	// 如果 configPath 为空，说明还没有初始化，需要查找
	// 但这里不使用锁，避免死锁。如果并发调用，可能会有重复查找，但不会出错

	usr, _ := user.Current()
	home := usr.HomeDir
	if home == "" {
		home = os.Getenv("HOME")
	}

	// 使用与 Syncthing 完全相同的逻辑（参考 unixConfigDir，syncthing/lib/locations/locations.go:212-237）
	// 但需要优先检查实际运行的 Syncthing 使用的路径（如果通过 -home 参数指定）
	logger.Info("开始查找配置文件路径（按照 Syncthing 源码逻辑）", zap.String("home", home))

	// 0. 优先检查：如果 SyncthingManager 已初始化，使用它记录的 configPath
	// 这样可以确保读取的是实际启动 Syncthing 时使用的配置文件路径
	logger.Info("步骤 0: 检查 SyncthingManager 的 configPath...")
	if manager := GetSyncthingManager(); manager != nil {
		syncthingHome := manager.GetConfigPath()
		if syncthingHome != "" {
			candidate := filepath.Join(syncthingHome, "config.xml")
			logger.Info("检查 SyncthingManager 路径", zap.String("candidate", candidate), zap.String("syncthingHome", syncthingHome))
			if fileExists(candidate) {
				configPath = candidate
				logger.Info("✓ 找到配置文件（从 SyncthingManager 获取）", zap.String("path", candidate))
				return configPath
			} else {
				logger.Info("✗ SyncthingManager 路径的配置文件不存在", zap.String("path", candidate))
			}
		} else {
			logger.Info("✗ SyncthingManager 的 configPath 为空")
		}
	} else {
		logger.Info("✗ SyncthingManager 未初始化")
	}

	// 1. Legacy: 如果设置了 $XDG_CONFIG_HOME，检查 $XDG_CONFIG_HOME/syncthing/config.xml
	// 注意：Syncthing 源码中这个检查会检查文件是否存在
	logger.Info("步骤 1: 检查 $XDG_CONFIG_HOME/syncthing/config.xml...")
	xdgConfigHome := os.Getenv("XDG_CONFIG_HOME")
	if xdgConfigHome != "" {
		candidate := filepath.Join(xdgConfigHome, "syncthing", "config.xml")
		logger.Info("检查 XDG_CONFIG_HOME 路径", zap.String("XDG_CONFIG_HOME", xdgConfigHome), zap.String("candidate", candidate))
		if fileExists(candidate) {
			configPath = candidate
			logger.Info("✓ 找到配置文件（XDG_CONFIG_HOME）", zap.String("path", candidate))
			return configPath
		} else {
			logger.Info("✗ XDG_CONFIG_HOME 路径的配置文件不存在", zap.String("path", candidate))
		}
	} else {
		logger.Info("✗ XDG_CONFIG_HOME 未设置")
	}

	// 2. Legacy: 检查 ~/.config/syncthing/config.xml（旧版路径，如果存在则优先使用）
	logger.Info("步骤 2: 检查 ~/.config/syncthing/config.xml（Legacy）...")
	candidate := filepath.Join(home, ".config", "syncthing", "config.xml")
	logger.Info("检查 Legacy 路径", zap.String("candidate", candidate))
	if fileExists(candidate) {
		configPath = candidate
		logger.Info("✓ 找到配置文件（Legacy）", zap.String("path", candidate))
		return configPath
	} else {
		logger.Info("✗ Legacy 路径的配置文件不存在", zap.String("path", candidate))
	}

	// 3. 如果 XDG_STATE_HOME 是绝对路径，使用 $XDG_STATE_HOME/syncthing/config.xml
	logger.Info("步骤 3: 检查 $XDG_STATE_HOME/syncthing/config.xml...")
	xdgStateHome := os.Getenv("XDG_STATE_HOME")
	if filepath.IsAbs(xdgStateHome) {
		candidate := filepath.Join(xdgStateHome, "syncthing", "config.xml")
		logger.Info("检查 XDG_STATE_HOME 路径", zap.String("XDG_STATE_HOME", xdgStateHome), zap.String("candidate", candidate))
		if fileExists(candidate) {
			configPath = candidate
			logger.Info("✓ 找到配置文件（XDG_STATE_HOME）", zap.String("path", candidate))
			return configPath
		} else {
			logger.Info("✗ XDG_STATE_HOME 路径的配置文件不存在", zap.String("path", candidate))
		}
	} else {
		logger.Info("✗ XDG_STATE_HOME 未设置或不是绝对路径", zap.String("XDG_STATE_HOME", xdgStateHome))
	}

	// 4. 默认使用 ~/.local/state/syncthing/config.xml（新版路径）
	logger.Info("步骤 4: 检查 ~/.local/state/syncthing/config.xml（默认路径）...")
	candidate = filepath.Join(home, ".local", "state", "syncthing", "config.xml")
	logger.Info("检查默认路径", zap.String("candidate", candidate))
	if fileExists(candidate) {
		configPath = candidate
		logger.Info("✓ 找到配置文件（默认）", zap.String("path", candidate))
		return configPath
	} else {
		logger.Info("✗ 默认路径的配置文件不存在", zap.String("path", candidate))
	}

	// 5. Windows 和 macOS 的路径（如果是在这些平台上）
	if runtime.GOOS == "windows" {
		if p := os.Getenv("LocalAppData"); p != "" {
			candidate = filepath.Join(p, "Syncthing", "config.xml")
			if fileExists(candidate) {
				configPath = candidate
				logger.Info("找到配置文件（Windows LocalAppData）", zap.String("path", candidate))
				return configPath
			}
		}
		if p := os.Getenv("AppData"); p != "" {
			candidate = filepath.Join(p, "Syncthing", "config.xml")
			if fileExists(candidate) {
				configPath = candidate
				logger.Info("找到配置文件（Windows AppData）", zap.String("path", candidate))
				return configPath
			}
		}
	}

	if runtime.GOOS == "darwin" {
		candidate = filepath.Join(home, "Library", "Application Support", "Syncthing", "config.xml")
		if fileExists(candidate) {
			configPath = candidate
			logger.Info("找到配置文件（macOS）", zap.String("path", candidate))
			return configPath
		}
	}

	// Fallback: 使用当前目录的 config.xml
	configPath = "config.xml"
	logger.Warn("未找到配置文件，使用默认路径", zap.String("path", "config.xml"))
	return configPath
}

func getApiKeyFromConfig() string {
	logger.Info("获取配置文件路径...")
	configPath := getConfigPath()
	logger.Info("配置文件路径", zap.String("path", configPath))
	type Gui struct {
		APIKey string `xml:"apikey"`
	}
	type Config struct {
		Gui Gui `xml:"gui"`
	}
	logger.Info("开始读取配置文件...")
	data, err := ioutil.ReadFile(configPath)
	if err != nil {
		logger.Warn("读取配置文件失败", zap.Error(err))
		return "" // 失败时用空
	}
	logger.Info("配置文件读取成功", zap.Int("size", len(data)))
	var cfg Config
	logger.Info("开始解析 XML...")
	err = xml.Unmarshal(data, &cfg)
	if err != nil {
		logger.Warn("解析 XML 失败", zap.Error(err))
		return ""
	}
	if cfg.Gui.APIKey == "" {
		logger.Info("配置文件中未找到 API Key")
		return ""
	}
	// 打印 API Key 的前 10 个字符用于调试（不打印完整 key 以保护安全）
	keyPreview := cfg.Gui.APIKey
	if len(keyPreview) > 10 {
		keyPreview = keyPreview[:10] + "..."
	}
	logger.Info("成功获取 API Key", zap.Int("length", len(cfg.Gui.APIKey)), zap.String("preview", keyPreview))
	return cfg.Gui.APIKey
}

func loadAndIndex() {
	mu.Lock()
	defer mu.Unlock()

	logger.Info("=== 开始加载和索引 ===")

	// 先检查 Syncthing 是否运行
	logger.Info("步骤 0: 检查 Syncthing 服务状态...")
	if !isSyncthingRunning() {
		logger.Info("Syncthing 服务未运行，尝试启动...")
		// 尝试启动 Syncthing
		mgr := GetSyncthingManager()
		if err := mgr.Start(); err != nil {
			logger.Warn("启动 Syncthing 失败，使用 config.xml", zap.Error(err))
			logger.Info("步骤 1: 从 config.xml 加载文件夹配置...")
			loadFoldersFromConfig()
			if len(folders) == 0 {
				logger.Warn("从 config.xml 加载后文件夹列表仍为空，请检查配置文件")
				logger.Info("=== 加载和索引完成（无文件夹） ===")
				return
			} else {
				logger.Info("从 config.xml 成功加载文件夹", zap.Int("count", len(folders)))
			}
		} else {
			logger.Info("Syncthing 启动成功，等待 API 就绪...")
			// 等待 Syncthing API 就绪（最多等待 10 秒）
			if err := mgr.WaitForAPI(10 * time.Second); err != nil {
				logger.Warn("等待 Syncthing API 就绪失败，使用 config.xml", zap.Error(err))
				loadFoldersFromConfig()
				if len(folders) == 0 {
					logger.Warn("从 config.xml 加载后文件夹列表仍为空")
					logger.Info("=== 加载和索引完成（无文件夹） ===")
					return
				} else {
					logger.Info("从 config.xml 成功加载文件夹", zap.Int("count", len(folders)))
				}
			} else {
				logger.Info("Syncthing API 已就绪，从 API 获取文件夹配置...")
				// 从 Syncthing API 获取文件夹配置
				syncthingFolders, err := loadFoldersFromSyncthing()
				if err != nil {
					logger.Warn("从 Syncthing API 获取文件夹失败，回退到 config.xml", zap.Error(err))
					loadFoldersFromConfig()
					if len(folders) == 0 {
						logger.Warn("从 config.xml 加载后文件夹列表仍为空")
						logger.Info("=== 加载和索引完成（无文件夹） ===")
						return
					} else {
						logger.Info("从 config.xml 成功加载文件夹", zap.Int("count", len(folders)))
					}
				} else {
					folders = syncthingFolders
					logger.Info("从 Syncthing API 获取到同步文件夹", zap.Int("count", len(folders)))
					for _, folder := range folders {
						logger.Info("同步文件夹", zap.String("id", folder.ID), zap.String("path", folder.Path), zap.Strings("sharedDevices", folder.SharedDevices))
					}
				}
			}
		}
	} else {
		logger.Info("Syncthing 服务正在运行")
		// 从 Syncthing API 获取完整的文件夹配置
		logger.Info("步骤 1: 尝试从 Syncthing API 获取文件夹配置...")
		syncthingFolders, err := loadFoldersFromSyncthing()
		if err != nil {
			logger.Warn("从 Syncthing API 获取文件夹失败，回退到 config.xml", zap.Error(err))
			// 回退到从 config.xml 加载
			logger.Info("步骤 2: 从 config.xml 加载文件夹配置...")
			loadFoldersFromConfig()
			// 确保从 config.xml 加载成功
			if len(folders) == 0 {
				logger.Warn("从 config.xml 加载后文件夹列表仍为空，请检查配置文件")
				logger.Info("=== 加载和索引完成（无文件夹） ===")
				return
			} else {
				logger.Info("从 config.xml 成功加载文件夹", zap.Int("count", len(folders)))
			}
		} else {
			folders = syncthingFolders
			logger.Info("从 Syncthing API 获取到同步文件夹", zap.Int("count", len(folders)))
			for _, folder := range folders {
				logger.Info("同步文件夹", zap.String("id", folder.ID), zap.String("path", folder.Path), zap.Strings("sharedDevices", folder.SharedDevices))
			}
		}
	}

	// 清空旧索引
	logger.Info("步骤 3: 清空旧索引...")
	if result := db.Session(&gorm.Session{AllowGlobalUpdate: true}).Delete(&File{}); result.Error != nil {
		logger.Error("清空旧索引失败", zap.Error(result.Error))
	} else {
		logger.Info("清空旧索引成功", zap.Int64("deleted", result.RowsAffected))
	}

	// 遍历所有同步文件夹
	logger.Info("步骤 4: 开始遍历和索引文件夹", zap.Int("total", len(folders)))
	for i, folder := range folders {
		logger.Info("开始索引文件夹", zap.Int("index", i+1), zap.Int("total", len(folders)), zap.String("id", folder.ID), zap.String("path", folder.Path))
		walkAndIndex(folder)
		logger.Info("完成索引文件夹", zap.Int("index", i+1), zap.Int("total", len(folders)), zap.String("id", folder.ID))
	}

	logger.Info("=== 加载和索引完成 ===")
}

// 展开路径中的 ~ 符号
func expandPath(path string) string {
	fmt.Printf("展开路径: %s\n", path)

	// 处理 ~ 开头的路径
	if strings.HasPrefix(path, "~/") {
		usr, err := user.Current()
		if err != nil {
			// 如果获取用户失败，尝试使用环境变量
			home := os.Getenv("HOME")
			if home == "" {
				fmt.Printf("无法获取用户主目录，返回原路径: %s\n", path)
				return path // 返回原路径
			}
			expanded := filepath.Join(home, path[2:])
			fmt.Printf("使用环境变量展开路径: %s -> %s\n", path, expanded)
			return expanded
		}
		expanded := filepath.Join(usr.HomeDir, path[2:])
		fmt.Printf("使用用户主目录展开路径: %s -> %s\n", path, expanded)
		return expanded
	}

	// 处理单独的 ~ 路径
	if path == "~" {
		usr, err := user.Current()
		if err != nil {
			home := os.Getenv("HOME")
			if home == "" {
				fmt.Printf("无法获取用户主目录，返回原路径: %s\n", path)
				return path
			}
			fmt.Printf("使用环境变量展开路径: %s -> %s\n", path, home)
			return home
		}
		fmt.Printf("使用用户主目录展开路径: %s -> %s\n", path, usr.HomeDir)
		return usr.HomeDir
	}

	fmt.Printf("路径无需展开: %s\n", path)
	return path
}

// 检查 Syncthing 是否正在运行
func isSyncthingRunning() bool {
	logger.Info("检查 Syncthing 状态", zap.String("url", "https://127.0.0.1:8384/rest/system/status"))

	// 使用 context 控制超时
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", "https://127.0.0.1:8384/rest/system/status", nil)
	if err != nil {
		logger.Error("创建请求失败", zap.Error(err))
		return false
	}

	// 添加 API Key（如果存在）
	logger.Info("开始获取 API Key...")
	apiKey := getApiKeyFromConfig()
	logger.Info("API Key 获取完成", zap.Bool("hasKey", apiKey != ""), zap.Int("keyLength", len(apiKey)))
	if apiKey != "" {
		// 根据 Syncthing 文档，可以使用 X-API-Key 或 Authorization: Bearer
		// 优先使用 X-API-Key
		req.Header.Set("X-API-Key", apiKey)
		// 同时设置 Authorization 头作为备选
		req.Header.Set("Authorization", "Bearer "+apiKey)
		logger.Info("已设置 API Key", zap.Int("length", len(apiKey)))
	} else {
		logger.Info("未找到 API Key，使用无认证请求")
	}

	// 创建 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	logger.Info("发送 HTTP 请求...")
	startTime := time.Now()
	resp, err := client.Do(req)
	duration := time.Since(startTime)
	if err != nil {
		logger.Warn("连接 Syncthing API 失败", zap.Error(err), zap.Duration("duration", duration))
		return false
	}
	defer resp.Body.Close()
	logger.Info("Syncthing API 响应", zap.Int("statusCode", resp.StatusCode), zap.Duration("duration", duration))

	// 403 可能表示 API Key 不正确，但 Syncthing 正在运行
	// 200 表示成功
	// 其他状态码表示 Syncthing 可能未运行或有问题
	if resp.StatusCode == 200 {
		return true
	} else if resp.StatusCode == 403 {
		// 403 表示 API Key 不正确，但 Syncthing 正在运行
		// 读取响应体查看具体错误
		body, _ := ioutil.ReadAll(resp.Body)
		logger.Warn("Syncthing API 返回 403（API Key 可能不正确）", zap.String("response", string(body)))
		// 即使 API Key 不正确，也认为 Syncthing 正在运行（因为能收到响应）
		return true
	}
	return false
}

// 从 Syncthing API 加载文件夹配置
func loadFoldersFromSyncthing() ([]FolderEntry, error) {
	// 构建 syncthing API URL
	syncthingURL := "https://127.0.0.1:8384/rest/config/folders"
	log.Printf("尝试连接 Syncthing API: %s", syncthingURL)

	// 创建请求
	req, err := http.NewRequest("GET", syncthingURL, nil)
	if err != nil {
		log.Printf("创建请求失败: %v", err)
		return nil, fmt.Errorf("failed to create request: %v", err)
	}

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		// 根据 Syncthing 文档，可以使用 X-API-Key 或 Authorization: Bearer
		req.Header.Set("X-API-Key", apiKey)
		req.Header.Set("Authorization", "Bearer "+apiKey)
		log.Printf("已设置 API Key (长度: %d)", len(apiKey))
	} else {
		log.Printf("未设置 API Key，使用默认认证")
	}

	// 发送请求（设置较短的超时，避免长时间等待）
	// 创建 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{
		Transport: tr,
		Timeout:   3 * time.Second, // 缩短超时时间到 3 秒
	}
	log.Printf("发送 HTTP 请求到 Syncthing API（超时: 3秒）...")
	startTime := time.Now()
	resp, err := client.Do(req)
	duration := time.Since(startTime)
	if err != nil {
		log.Printf("HTTP 请求失败（耗时: %v）: %v", duration, err)
		return nil, fmt.Errorf("failed to send request to syncthing: %v", err)
	}
	defer resp.Body.Close()
	log.Printf("收到响应，状态码: %d（耗时: %v）", resp.StatusCode, duration)

	// 检查响应状态
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		log.Printf("Syncthing API 返回错误状态码 %d: %s", resp.StatusCode, string(body))
		return nil, fmt.Errorf("syncthing API returned status %d: %s", resp.StatusCode, string(body))
	}

	// 解析响应
	log.Printf("解析 Syncthing API 响应...")
	var syncthingFolders []map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&syncthingFolders); err != nil {
		log.Printf("解析响应失败: %v", err)
		return nil, fmt.Errorf("failed to decode response: %v", err)
	}
	log.Printf("成功解析到 %d 个文件夹配置", len(syncthingFolders))

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
	// 确保 configPath 已设置
	if configPath == "" {
		configPath = getConfigPath()
	}

	fmt.Printf("尝试从 config.xml 加载文件夹，路径: %s\n", configPath)

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

	// 如果解析后文件夹列表为空，记录警告
	if len(folders) == 0 {
		log.Printf("警告: config.xml 中没有找到文件夹配置")
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
	root := expandPath(folder.Path)
	log.Printf("开始索引文件夹: [%s] %s (展开后: %s)", folder.ID, folder.Path, root)

	// 检查路径是否存在
	if _, err := os.Stat(root); os.IsNotExist(err) {
		log.Printf("警告: 文件夹路径不存在: %s", root)
		return
	}

	log.Printf("开始遍历文件夹: %s", root)
	fileCount := 0
	startTime := time.Now()
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

	duration := time.Since(startTime)
	log.Printf("文件夹 [%s] 索引完成，共 %d 个文件，耗时: %v", folder.ID, fileCount, duration)
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
