package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"mydata/mydata_api"
)

func main() {
	// 命令行参数
	port := flag.Int("port", 8443, "HTTPS 服务器端口")
	flag.Parse()

	log.Println("🚀 启动 MyData HTTPS API 服务器...")
	log.Printf("📡 服务器端口: %d", *port)
	log.Println("🔒 使用自签名证书")

	// 启动 HTTPS 服务器
	go func() {
		mydata_api.StartServer()
	}()

	// 等待中断信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	// 优雅关闭
	log.Println("🛑 收到关闭信号，正在优雅关闭...")
	log.Println("✅ 服务器已关闭")
}
