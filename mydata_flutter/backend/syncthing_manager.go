package backend

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"time"
)

// SyncthingManager 管理 Syncthing 进程
type SyncthingManager struct {
	cmd        *exec.Cmd
	ctx        context.Context
	cancel     context.CancelFunc
	mu         sync.Mutex
	isRunning  bool
	configPath string
	dataPath   string
	exePath    string
	logFile    *os.File
	// customExePath 允许设置自定义的可执行文件路径（用于 Android 等平台）
	customExePath string
}

var (
	syncthingManager *SyncthingManager
	managerOnce      sync.Once
)

// GetSyncthingManager 获取 Syncthing 管理器单例
func GetSyncthingManager() *SyncthingManager {
	managerOnce.Do(func() {
		syncthingManager = NewSyncthingManager()
	})
	return syncthingManager
}

// NewSyncthingManager 创建新的 Syncthing 管理器
func NewSyncthingManager() *SyncthingManager {
	ctx, cancel := context.WithCancel(context.Background())

	// 获取可执行文件路径
	exePath := getSyncthingExecutablePath()

	// 获取配置和数据目录
	configPath, dataPath := getSyncthingPaths()

	return &SyncthingManager{
		ctx:        ctx,
		cancel:     cancel,
		configPath: configPath,
		dataPath:   dataPath,
		exePath:    exePath,
	}
}

// getSyncthingExecutablePath 获取 Syncthing 可执行文件路径
func getSyncthingExecutablePath() string {
	// 检查是否有自定义路径（通过 SetSyncthingPath 设置）
	if syncthingManager != nil && syncthingManager.customExePath != "" {
		if _, err := os.Stat(syncthingManager.customExePath); err == nil {
			return syncthingManager.customExePath
		}
	}

	projectRoot := getProjectRoot()

	// 1. 优先查找 mydata_flutter/bin/syncthing
	syncthingPath := filepath.Join(projectRoot, "bin", "syncthing")
	if info, err := os.Stat(syncthingPath); err == nil {
		if runtime.GOOS != "windows" {
			if info.Mode().Perm()&0111 != 0 {
				return syncthingPath
			}
		} else {
			return syncthingPath
		}
	}

	// 2. 查找 mydata_flutter/syncthing（直接放在项目根目录）
	syncthingPath2 := filepath.Join(projectRoot, "syncthing")
	if info, err := os.Stat(syncthingPath2); err == nil {
		if runtime.GOOS != "windows" {
			if info.Mode().Perm()&0111 != 0 {
				return syncthingPath2
			}
		} else {
			return syncthingPath2
		}
	}

	// 3. 如果项目目录下没有，尝试使用系统 PATH 中的 syncthing
	if path, err := exec.LookPath("syncthing"); err == nil {
		return path
	}

	// 4. 如果都找不到，返回 bin 目录下的路径（即使不存在，让用户知道需要编译）
	return syncthingPath
}

// getProjectRoot 获取项目根目录
func getProjectRoot() string {
	// 从当前工作目录向上查找，直到找到包含 bin/syncthing 或 syncthing 文件的目录
	wd, err := os.Getwd()
	if err != nil {
		wd = "."
	}

	dir := wd
	for {
		// 检查 bin/syncthing
		binDir := filepath.Join(dir, "bin")
		if info, err := os.Stat(binDir); err == nil && info.IsDir() {
			syncthingPath := filepath.Join(binDir, "syncthing")
			if _, err := os.Stat(syncthingPath); err == nil {
				return dir
			}
		}

		// 检查根目录下的 syncthing 文件
		syncthingPath := filepath.Join(dir, "syncthing")
		if info, err := os.Stat(syncthingPath); err == nil && !info.IsDir() {
			return dir
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			// 到达根目录
			break
		}
		dir = parent
	}

	// 如果找不到，尝试使用可执行文件所在目录
	// 获取可执行文件路径
	execPath, err := os.Executable()
	if err == nil {
		execDir := filepath.Dir(execPath)
		// 从可执行文件目录向上查找
		dir = execDir
		for {
			binDir := filepath.Join(dir, "bin")
			if info, err := os.Stat(binDir); err == nil && info.IsDir() {
				syncthingPath := filepath.Join(binDir, "syncthing")
				if _, err := os.Stat(syncthingPath); err == nil {
					return dir
				}
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}

	// 如果都找不到，返回当前目录
	return wd
}

// getSyncthingPaths 获取 Syncthing 配置和数据目录
func getSyncthingPaths() (configPath, dataPath string) {
	// 检查是否设置了 Android 数据目录
	dataDir := os.Getenv("MYDATA_DATA_DIR")
	if dataDir != "" {
		// Android 环境：使用应用数据目录
		configPath = dataDir
		dataPath = dataDir
		return configPath, dataPath
	}

	home, err := os.UserHomeDir()
	if err != nil {
		home = "."
	}

	switch runtime.GOOS {
	case "windows":
		configPath = filepath.Join(home, "AppData", "Local", "Syncthing")
		dataPath = configPath
	case "darwin":
		configPath = filepath.Join(home, "Library", "Application Support", "Syncthing")
		dataPath = configPath
	default: // linux, etc.
		// 优先使用新版路径
		configPath = filepath.Join(home, ".local", "state", "syncthing")
		dataPath = filepath.Join(home, ".local", "share", "syncthing")

		// 如果新版路径不存在，尝试旧版路径
		if _, err := os.Stat(configPath); os.IsNotExist(err) {
			configPath = filepath.Join(home, ".config", "syncthing")
			dataPath = configPath
		}
	}

	return configPath, dataPath
}

// Start 启动 Syncthing 进程
func (sm *SyncthingManager) Start() error {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	if sm.isRunning {
		return fmt.Errorf("Syncthing 已经在运行")
	}

	// 检查可执行文件是否存在
	if _, err := os.Stat(sm.exePath); os.IsNotExist(err) {
		return fmt.Errorf("Syncthing 可执行文件不存在: %s\n请先编译 Syncthing: cd syncthing && go run build.go", sm.exePath)
	}

	// 确保配置目录存在
	if err := os.MkdirAll(sm.configPath, 0755); err != nil {
		return fmt.Errorf("无法创建配置目录: %v", err)
	}

	// 创建日志文件
	logPath := filepath.Join(sm.dataPath, "syncthing.log")
	if err := os.MkdirAll(filepath.Dir(logPath), 0755); err != nil {
		return fmt.Errorf("无法创建日志目录: %v", err)
	}

	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return fmt.Errorf("无法创建日志文件: %v", err)
	}
	sm.logFile = logFile

	// 构建命令
	cmd := exec.CommandContext(sm.ctx, sm.exePath,
		"-no-browser",          // 不自动打开浏览器
		"-no-restart",          // 不自动重启（由我们管理）
		"-home", sm.configPath, // 指定配置目录
	)

	// 设置工作目录
	cmd.Dir = sm.dataPath

	// 重定向输出到日志文件
	cmd.Stdout = io.MultiWriter(logFile, os.Stdout)
	cmd.Stderr = io.MultiWriter(logFile, os.Stderr)

	// 启动进程
	if err := cmd.Start(); err != nil {
		logFile.Close()
		return fmt.Errorf("启动 Syncthing 失败: %v", err)
	}

	sm.cmd = cmd
	sm.isRunning = true

	log.Printf("✅ Syncthing 已启动 (PID: %d, 配置目录: %s)", cmd.Process.Pid, sm.configPath)

	// 在后台等待进程结束
	go sm.waitForProcess()

	return nil
}

// waitForProcess 等待进程结束并处理
func (sm *SyncthingManager) waitForProcess() {
	err := sm.cmd.Wait()

	sm.mu.Lock()
	defer sm.mu.Unlock()

	sm.isRunning = false

	if sm.logFile != nil {
		sm.logFile.Close()
		sm.logFile = nil
	}

	if err != nil {
		log.Printf("⚠️  Syncthing 进程异常退出: %v", err)
	} else {
		log.Printf("ℹ️  Syncthing 进程已停止")
	}
}

// Stop 停止 Syncthing 进程
func (sm *SyncthingManager) Stop() error {
	sm.mu.Lock()
	defer sm.mu.Unlock()

	if !sm.isRunning || sm.cmd == nil {
		return nil
	}

	log.Printf("正在停止 Syncthing (PID: %d)...", sm.cmd.Process.Pid)

	// 取消上下文，这会发送 SIGTERM 给进程
	sm.cancel()

	// 等待进程结束，最多等待 5 秒
	done := make(chan error, 1)
	go func() {
		done <- sm.cmd.Wait()
	}()

	select {
	case <-time.After(5 * time.Second):
		// 如果 5 秒后还没结束，强制杀死
		log.Printf("⚠️  Syncthing 未在 5 秒内停止，强制终止...")
		if err := sm.cmd.Process.Kill(); err != nil {
			return fmt.Errorf("强制终止 Syncthing 失败: %v", err)
		}
		<-done // 等待 Wait 返回
	case err := <-done:
		if err != nil {
			log.Printf("⚠️  Syncthing 停止时出错: %v", err)
		}
	}

	sm.isRunning = false

	if sm.logFile != nil {
		sm.logFile.Close()
		sm.logFile = nil
	}

	log.Printf("✅ Syncthing 已停止")

	// 重新创建上下文和取消函数，以便下次启动
	sm.ctx, sm.cancel = context.WithCancel(context.Background())

	return nil
}

// IsRunning 检查 Syncthing 是否正在运行
func (sm *SyncthingManager) IsRunning() bool {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	return sm.isRunning
}

// GetConfigPath 获取配置目录路径
func (sm *SyncthingManager) GetConfigPath() string {
	return sm.configPath
}

// GetDataPath 获取数据目录路径
func (sm *SyncthingManager) GetDataPath() string {
	return sm.dataPath
}

// GetExecutablePath 获取可执行文件路径
func (sm *SyncthingManager) GetExecutablePath() string {
	if sm.customExePath != "" {
		return sm.customExePath
	}
	return sm.exePath
}

// SetExecutablePath 设置自定义的可执行文件路径（用于 Android 等平台）
func (sm *SyncthingManager) SetExecutablePath(path string) {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	sm.customExePath = path
	// 如果路径已设置，更新 exePath
	if path != "" {
		sm.exePath = path
	}
}

// SetDataPaths 设置配置和数据目录路径（用于 Android 等平台）
func (sm *SyncthingManager) SetDataPaths(configPath, dataPath string) {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	sm.configPath = configPath
	sm.dataPath = dataPath
}

// WaitForAPI 等待 Syncthing API 就绪
func (sm *SyncthingManager) WaitForAPI(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		if !sm.IsRunning() {
			return fmt.Errorf("Syncthing 进程未运行")
		}

		// 尝试连接 API
		tr := &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}
		client := &http.Client{Transport: tr}
		resp, err := client.Get("https://127.0.0.1:8384/rest/system/status")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				return nil
			}
		}

		time.Sleep(500 * time.Millisecond)
	}

	return fmt.Errorf("等待 Syncthing API 超时（%v）", timeout)
}
