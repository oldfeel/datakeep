// Package mdst 提供 gomobile 可用的 Syncthing 进程内薄封装。
// 架构对齐 sushitrain（进程内节点 + 简单类型 API），实现自写，不复制其源码。
// 同一套代码供 iOS（xcframework）与 Android（AAR）使用；桌面暂用外置 syncthing。
package mdst

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"sync"

	"github.com/syncthing/syncthing/lib/build"
	"github.com/syncthing/syncthing/lib/config"
	"github.com/syncthing/syncthing/lib/events"
	"github.com/syncthing/syncthing/lib/locations"
	"github.com/syncthing/syncthing/lib/logger"
	"github.com/syncthing/syncthing/lib/protocol"
	"github.com/syncthing/syncthing/lib/svcutil"
	"github.com/syncthing/syncthing/lib/syncthing"
	"github.com/thejerf/suture/v4"
)

// Client 是移动端持有的进程内 Syncthing 节点。
type Client struct {
	homePath  string
	filesPath string
	deviceName string

	mu      sync.Mutex
	app     *syncthing.App
	cancel  context.CancelFunc
	cfg     config.Wrapper
	running bool
	lastErr string
	deviceID string
}

// NewClient 创建客户端。
// homePath: 配置/证书/数据库目录（Android filesDir；iOS Application Support/syncthing）
// filesPath: 默认同步数据根（可为 ""）
func NewClient(homePath, filesPath string) *Client {
	build.Version = "v1.28.1-datakeep"
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

	early := suture.New("early", svcutil.SpecWithDebugLogger(logger.DefaultLogger))
	early.ServeBackground(ctx)

	evLogger := events.NewLogger()
	early.Add(evLogger)

	// 移动端不创建 default 文件夹；端口探测在沙盒里不可靠，跳过
	cfgWrapper, err := syncthing.LoadConfigAtStartup(
		locations.Get(locations.ConfigFile),
		cert,
		evLogger,
		true,  // allowNewerConfig
		true,  // noDefaultFolder
		true,  // skipPortProbing
	)
	if err != nil {
		cancel()
		c.lastErr = err.Error()
		return fmt.Errorf("配置: %w", err)
	}
	early.Add(cfgWrapper)

	// 固定 GUI 到本机 8384，供 Dart shelf 代理
	cfgWrapper.Modify(func(cfg *config.Configuration) {
		cfg.GUI.RawAddress = "127.0.0.1:8384"
		cfg.GUI.Enabled = true
		if c.deviceName != "" {
			for i := range cfg.Devices {
				if cfg.Devices[i].DeviceID == protocol.NewDeviceID(cert.Certificate[0]) {
					cfg.Devices[i].Name = c.deviceName
				}
			}
		}
	})

	dbFile := locations.Get(locations.Database)
	ldb, err := syncthing.OpenDBBackend(dbFile, cfgWrapper.Options().DatabaseTuning)
	if err != nil {
		cancel()
		c.lastErr = err.Error()
		return fmt.Errorf("数据库: %w", err)
	}

	app, err := syncthing.New(cfgWrapper, ldb, evLogger, cert, syncthing.Options{
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
