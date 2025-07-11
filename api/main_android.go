//go:build android
// +build android

package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
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
	androidData := os.Getenv("ANDROID_DATA")
	if androidData == "" {
		androidData = "/data/data/com.nutomic.syncthingandroid"
	}
	dbPath := filepath.Join(androidData, "files", "mydata.db")
	fmt.Printf("数据库路径: %s\n", dbPath)

	db, err = gorm.Open(sqlite.Open(dbPath), &gorm.Config{})
	if err != nil {
		log.Fatal("failed to connect database:", err)
	}
	if err := db.AutoMigrate(&File{}); err != nil {
		log.Fatal("auto migrate failed:", err)
	}

	// 获取 config.xml 路径（Android 版本）
	configPath = getConfigPath()
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
	app.Get("/api/folder/:folderId/preview", filePreviewHandler)
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
	// 从环境变量获取路径，而不是硬编码
	androidData := os.Getenv("ANDROID_DATA")
	if androidData == "" {
		androidData = "/data/data/com.nutomic.syncthingandroid"
	}

	// 设置 Android 特定的环境变量
	os.Setenv("ANDROID_DATA", androidData)

	// 使用环境变量中的路径，而不是硬编码
	filesDir := filepath.Join(androidData, "files")
	cacheDir := filepath.Join(androidData, "cache")

	// 只记录路径，不尝试创建（由 Java 端负责创建）
	fmt.Printf("Android 文件目录: %s\n", filesDir)
	fmt.Printf("Android 缓存目录: %s\n", cacheDir)
}

// 导出函数供 Android 调用
func main() {
	AndroidMain()
}
