// Package mdst 提供 gomobile 可用的 Syncthing 进程内薄封装。
// 架构对齐 sushitrain（进程内节点 + 简单类型 API），实现自写，不复制其源码。
// 同一套代码供 iOS（xcframework）与 Android（AAR）使用；桌面暂用外置 syncthing。
package mdst

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/syncthing/syncthing/lib/build"
	"github.com/syncthing/syncthing/lib/config"
	"github.com/syncthing/syncthing/lib/events"
	"github.com/syncthing/syncthing/lib/locations"
	"github.com/syncthing/syncthing/lib/protocol"
	"github.com/syncthing/syncthing/lib/svcutil"
	"github.com/syncthing/syncthing/lib/syncthing"
	"github.com/thejerf/suture/v4"
)

// Client 是移动端持有的进程内 Syncthing 节点。
type Client struct {
	homePath   string
	filesPath  string
	deviceName string

	mu       sync.Mutex
	app      *syncthing.App
	cancel   context.CancelFunc
	cfg      config.Wrapper
	running  bool
	lastErr  string
	deviceID string
}

// NewClient 创建客户端。
// homePath: 配置/证书/数据库目录（Android filesDir；iOS Application Support/syncthing）
// filesPath: 默认同步数据根（可为 ""）
func NewClient(homePath, filesPath string) *Client {
	build.Version = "v2.1.3-datakeep"
	build.User = "datakeep"
	build.Host = "datakeep-" + runtime.GOOS

	return &Client{
		homePath:  homePath,
		filesPath: filesPath,
	}
}

// SetDeviceName 在 Start 前设置本机设备显示名。
func (c *Client) SetDeviceName(name string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.deviceName = name
}

// Start 加载配置并启动节点。可重复调用：已运行则直接成功。
func (c *Client) Start() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.running && c.app != nil {
		return nil
	}

	if err := os.MkdirAll(c.homePath, 0o700); err != nil {
		c.lastErr = err.Error()
		return err
	}
	if c.filesPath != "" {
		_ = os.MkdirAll(c.filesPath, 0o755)
	}

	if err := locations.SetBaseDir(locations.ConfigBaseDir, c.homePath); err != nil {
		c.lastErr = err.Error()
		return err
	}
	if err := locations.SetBaseDir(locations.DataBaseDir, c.homePath); err != nil {
		c.lastErr = err.Error()
		return err
	}
	if c.filesPath != "" {
		_ = locations.SetBaseDir(locations.UserHomeBaseDir, c.filesPath)
	}

	cert, err := syncthing.LoadOrGenerateCertificate(
		locations.Get(locations.CertFile),
		locations.Get(locations.KeyFile),
	)
	if err != nil {
		c.lastErr = err.Error()
		return fmt.Errorf("证书: %w", err)
	}
	c.deviceID = protocol.NewDeviceID(cert.Certificate[0]).String()

	ctx, cancel := context.WithCancel(context.Background())
	c.cancel = cancel

	early := suture.New("early", svcutil.SpecWithDebugLogger())
	early.ServeBackground(ctx)

	evLogger := events.NewLogger()
	early.Add(evLogger)

	// 端口探测在沙盒里不可靠，跳过
	cfgWrapper, err := syncthing.LoadConfigAtStartup(
		locations.Get(locations.ConfigFile),
		cert,
		evLogger,
		true, // allowNewerConfig
		true, // skipPortProbing
	)
	if err != nil {
		cancel()
		c.lastErr = err.Error()
		return fmt.Errorf("配置: %w", err)
	}
	early.Add(cfgWrapper)

	myID := protocol.NewDeviceID(cert.Certificate[0])
	defaultPath := filepath.Join(c.filesPath, "default")
	if c.filesPath == "" {
		defaultPath = filepath.Join(c.homePath, "Sync", "default")
	}
	_ = os.MkdirAll(defaultPath, 0o755)
	_ = os.MkdirAll(filepath.Join(defaultPath, ".stfolder"), 0o755)

	cfgWrapper.Modify(func(cfg *config.Configuration) {
		cfg.GUI.RawAddress = "127.0.0.1:8384"
		cfg.GUI.Enabled = true
		cfg.Options.RawListenAddresses = []string{
			"tcp://0.0.0.0:22000",
			"dynamic+https://relays.syncthing.net/endpoint",
		}
		// 对齐 sushitrain：iOS 忽略权限位、关闭 FSWatcher（沙盒下 watch 常误报）
		cfg.Defaults.Folder.IgnorePerms = true
		if build.IsIOS {
			cfg.Defaults.Folder.FSWatcherEnabled = false
		}

		// 保留/创建 default 文件夹，路径改到可写的 filesPath（勿再删除）
		foundDefault := false
		for i := range cfg.Folders {
			if cfg.Folders[i].ID != "default" {
				continue
			}
			cfg.Folders[i].Path = defaultPath
			cfg.Folders[i].IgnorePerms = true
			if build.IsIOS {
				cfg.Folders[i].FSWatcherEnabled = false
			}
			if cfg.Folders[i].Label == "" {
				cfg.Folders[i].Label = "Default Folder"
			}
			hasLocal := false
			for _, d := range cfg.Folders[i].Devices {
				if d.DeviceID == myID {
					hasLocal = true
					break
				}
			}
			if !hasLocal {
				cfg.Folders[i].Devices = append(cfg.Folders[i].Devices, config.FolderDeviceConfiguration{
					DeviceID: myID,
				})
			}
			foundDefault = true
		}
		if !foundDefault && len(cfg.Folders) == 0 {
			f := cfg.Defaults.Folder
			f.ID = "default"
			f.Label = "Default Folder"
			f.Path = defaultPath
			f.IgnorePerms = true
			if build.IsIOS {
				f.FSWatcherEnabled = false
			}
			f.Devices = []config.FolderDeviceConfiguration{{DeviceID: myID}}
			cfg.Folders = append(cfg.Folders, f)
		}

		// iOS：容器绝对路径每次启动可能变化；对齐 sushitrain 把文件夹落到当前 Documents/<id>
		if build.IsIOS && c.filesPath != "" {
			c.normalizeIOSFolderPaths(cfg)
		}

		if c.deviceName != "" {
			for i := range cfg.Devices {
				if cfg.Devices[i].DeviceID == myID {
					cfg.Devices[i].Name = c.deviceName
				}
			}
		}
	})

	if err := syncthing.TryMigrateDatabase(ctx, 0); err != nil {
		cancel()
		c.lastErr = err.Error()
		return fmt.Errorf("数据库迁移: %w", err)
	}

	sdb, err := syncthing.OpenDatabase(locations.Get(locations.Database), 0)
	if err != nil {
		cancel()
		c.lastErr = err.Error()
		return fmt.Errorf("数据库: %w", err)
	}

	app, err := syncthing.New(cfgWrapper, sdb, evLogger, cert, syncthing.Options{
		NoUpgrade: true,
	})
	if err != nil {
		cancel()
		c.lastErr = err.Error()
		return fmt.Errorf("创建 App: %w", err)
	}

	if err := app.Start(); err != nil {
		cancel()
		c.lastErr = err.Error()
		return fmt.Errorf("启动: %w", err)
	}

	c.app = app
	c.cfg = cfgWrapper
	c.running = true
	c.lastErr = ""
	return nil
}

// normalizeIOSFolderPaths 对齐 sushitrain：
// iOS 应用容器路径会变，配置里旧的绝对路径会失效；把可管理的文件夹纠正到当前 Documents 下。
func (c *Client) normalizeIOSFolderPaths(cfg *config.Configuration) {
	filesRoot, err := filepath.Abs(c.filesPath)
	if err != nil {
		filesRoot = filepath.Clean(c.filesPath)
	}
	for i := range cfg.Folders {
		f := &cfg.Folders[i]
		f.IgnorePerms = true
		f.FSWatcherEnabled = false

		std := filepath.Join(filesRoot, f.ID)
		legacy := filepath.Join(filesRoot, "sync", f.ID)
		cur := strings.TrimSpace(f.Path)

		target := ""
		switch {
		case dirExists(cur) && pathUnderRoot(cur, filesRoot):
			// 已在当前容器 Documents 内且可访问，保持（含旧版 Documents/sync/<id>）
			target = cur
		case dirExists(legacy):
			target = legacy
		case dirExists(std):
			target = std
		default:
			// 旧绝对路径失效：落到 Documents/<id>（与 sushitrain 一致）
			_ = os.MkdirAll(std, 0o755)
			marker := f.MarkerName
			if marker == "" {
				marker = ".stfolder"
			}
			_ = os.MkdirAll(filepath.Join(std, marker), 0o755)
			target = std
		}
		if target != "" && f.Path != target {
			fmt.Printf("[syncthing_core] iOS 纠正文件夹路径 %s: %s -> %s\n", f.ID, f.Path, target)
			f.Path = target
		}
	}
}

func dirExists(p string) bool {
	if p == "" {
		return false
	}
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

func pathUnderRoot(path, root string) bool {
	absPath, err := filepath.Abs(path)
	if err != nil {
		absPath = filepath.Clean(path)
	}
	absRoot, err := filepath.Abs(root)
	if err != nil {
		absRoot = filepath.Clean(root)
	}
	// 去掉 /private 前缀差异
	absPath = strings.TrimPrefix(absPath, "/private")
	absRoot = strings.TrimPrefix(absRoot, "/private")
	if absPath == absRoot {
		return true
	}
	rel, err := filepath.Rel(absRoot, absPath)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// Stop 停止节点。
func (c *Client) Stop() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.app != nil {
		c.app.Stop(svcutil.ExitSuccess)
		c.app = nil
	}
	if c.cancel != nil {
		c.cancel()
		c.cancel = nil
	}
	c.running = false
}

// IsRunning 是否已启动。
func (c *Client) IsRunning() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.running && c.app != nil
}

// DeviceID 返回本机设备 ID（Start 后可用）。
func (c *Client) DeviceID() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.deviceID
}

// LastError 最近一次 Start 失败信息。
func (c *Client) LastError() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.lastErr
}

// HomePath 配置目录。
func (c *Client) HomePath() string {
	return c.homePath
}

// FilesPath 默认同步根目录。
func (c *Client) FilesPath() string {
	return c.filesPath
}
