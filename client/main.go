package main

import (
	"context"
	"embed"
	"log"
	"mydata/mydata_api"
	"os"
	"os/signal"
	"syscall"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	go mydata_api.StartServer()

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
		// 取消上下文
		cancel()
		// 强制退出
		os.Exit(0)
	}()

	// 创建应用实例
	app := NewApp()

	// 运行应用
	err := wails.Run(&options.App{
		Title:             "MyData",
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
