//go:build android
// +build android

package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// AndroidMain 是 Android 版本的入口函数
func AndroidMain() {
	fmt.Println("=== MyData API Android 版本启动 ===")

	// 设置 Android 特定的配置
	setupAndroidConfig()

	// 初始化数据库
	var err error
	db, err = gorm.Open(sqlite.Open("/data/data/com.mydata.app/files/mydata.db"), &gorm.Config{})
	if err != nil {
		log.Fatal("failed to connect database:", err)
	}
	if err := db.AutoMigrate(&File{}); err != nil {
		log.Fatal("auto migrate failed:", err)
	}

	// 获取 config.xml 路径（Android 版本）
	configPath = "/data/data/com.nutomic.syncthingandroid/files/config.xml"
	fmt.Println("Syncthing config.xml:", configPath)

	// 准备索引
	fmt.Println("准备索引")
	loadAndIndex()
	fmt.Println("索引完成")

	// 监听 config.xml 变化
	go watchConfig()

	// 启动 Fiber API 服务（使用 Android 可访问的端口）
	app := fiber.New()
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowHeaders: "*",
		AllowMethods: "GET,POST,OPTIONS",
	}))

	// API 路由
	app.Get("/api/folder/:folderId", folderFilesHandler)
	app.Get("/api/devices", devicesHandler)
	app.Get("/api/device/:deviceId/folders", deviceFoldersHandler)

	// 健康检查端点
	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status":   "ok",
			"service":  "mydata-api",
			"platform": "android",
		})
	})

	// 在后台启动服务
	go func() {
		fmt.Println("启动 API 服务在端口 8080...")
		if err := app.Listen(":8080"); err != nil {
			log.Printf("API 服务启动失败: %v", err)
		}
	}()

	// 等待信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	fmt.Println("MyData API 已启动，等待信号...")
	<-sigChan

	fmt.Println("收到退出信号，正在关闭...")
}

// setupAndroidConfig 设置 Android 特定的配置
func setupAndroidConfig() {
	// 设置 Android 特定的环境变量
	os.Setenv("ANDROID_DATA", "/data/data/com.mydata.app")

	// 创建必要的目录
	dirs := []string{
		"/data/data/com.mydata.app/files",
		"/data/data/com.mydata.app/cache",
	}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			fmt.Printf("创建目录失败 %s: %v\n", dir, err)
		}
	}
}

// 导出函数供 Android 调用
func main() {
	AndroidMain()
}
