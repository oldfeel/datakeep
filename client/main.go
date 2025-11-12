package main

import (
	"context"
	"embed"
	"log"
	"mydata/backend"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	// 启动后端 API 服务
	go backend.StartServer()

	// 启动 Syncthing 管理器
	syncthingMgr := backend.GetSyncthingManager()
	if err := syncthingMgr.Start(); err != nil {
		log.Printf("⚠️  启动 Syncthing 失败: %v", err)
		log.Printf("   可执行文件路径: %s", syncthingMgr.GetExecutablePath())
		log.Printf("   提示: 如果 Syncthing 未编译，请运行: cd syncthing && go run build.go")
		// 不阻止应用启动，允许用户手动启动 Syncthing
	} else {
		// 等待 Syncthing API 就绪（最多等待 10 秒）
		if err := syncthingMgr.WaitForAPI(10 * time.Second); err != nil {
			log.Printf("⚠️  Syncthing API 未就绪: %v", err)
		} else {
			log.Printf("✅ Syncthing API 已就绪")
		}
	}

	// 创建一个带取消功能的上下文
	_, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 创建一个通道来接收信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// 创建一个 goroutine 来监听信号
	go func() {
		sig := <-sigChan
		log.Printf("收到信号: %v", sig)

		// 停止 Syncthing
		if err := syncthingMgr.Stop(); err != nil {
			log.Printf("停止 Syncthing 时出错: %v", err)
		}

		// 取消上下文
		cancel()
		// 强制退出
		os.Exit(0)
	}()

	// 创建应用实例
	app := NewApp()

	// 运行应用
	err := wails.Run(&options.App{
		Title:             "我的数据",
		Width:             1024,
		Height:            768,
		MinWidth:          800,
		MinHeight:         600,
		MaxWidth:          1920,
		MaxHeight:         1080,
		DisableResize:     false,
		Fullscreen:        false,
		Frameless:         false,
		StartHidden:       false,
		HideWindowOnClose: false,
		BackgroundColour:  &options.RGBA{R: 255, G: 255, B: 255, A: 1},
		Assets:            assets,
		Menu:              nil,
		Logger:            nil,
		OnStartup:         app.startup,
		OnDomReady:        nil,
		OnBeforeClose:     nil,
		OnShutdown:        nil,
		WindowStartState:  options.Normal,
		Bind: []interface{}{
			app,
		},
	})

	if err != nil {
		log.Fatal(err)
	}
}
