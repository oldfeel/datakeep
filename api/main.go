package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"gopkg.in/natefinch/lumberjack.v2"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

var logger *zap.Logger

func initZapLogger() *zap.Logger {
	logDir := "logs"
	logFile := filepath.Join(logDir, "app.log")
	if _, err := os.Stat(logDir); os.IsNotExist(err) {
		os.Mkdir(logDir, 0755)
	}
	ljWriter := &lumberjack.Logger{
		Filename:   logFile,
		MaxSize:    20, // 单个文件最大20MB
		MaxBackups: 0,  // 不限制备份数量
		MaxAge:     30, // 最多保存30天
		Compress:   false,
	}
	encoder := zapcore.NewConsoleEncoder(zap.NewDevelopmentEncoderConfig())
	core := zapcore.NewCore(encoder, zapcore.AddSync(ljWriter), zapcore.DebugLevel)
	logger := zap.New(core, zap.AddCaller(), zap.AddCallerSkip(1))
	zap.ReplaceGlobals(logger) // 让 zap.L() 可全局调用
	return logger
}

func main() {
	logger = initZapLogger()
	logger.Info("zap + lumberjack 日志系统初始化完成")
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
	db, err = gorm.Open(sqlite.Open("mydata.db"), &gorm.Config{})
	if err != nil {
		log.Fatal("failed to connect database:", err)
	}
	// 自动迁移设备表和文件夹表
	if err := db.AutoMigrate(&File{}, &DeviceInfo{}, &FolderInfo{}); err != nil {
		log.Fatal("auto migrate failed:", err)
	}

	// 2. 获取 config.xml 路径
	configPath = getConfigPath()
	fmt.Println("Syncthing config.xml:", configPath)

	// 3. 异步启动索引
	fmt.Println("启动异步索引...")
	go func() {
		loadAndIndex()
	}()

	// 如果是强制索引模式，立即执行
	if len(os.Args) > 1 && os.Args[1] == "-force" {
		fmt.Println("强制重新索引模式...")
		loadAndIndex()
	}

	// 4. 监听 config.xml 变化
	go watchConfig()

	// 5. 启动 Fiber API 服务
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
	app.Get("/api/device/:deviceId/folders/", deviceFoldersHandler)
	app.Get("/api/device/:deviceId/folders/:folderId", deviceFoldersHandler)
	app.Get("/api/device/:deviceId/folders/:folderId/", deviceFoldersHandler)
	app.Get("/api/deviceid", getLocalDeviceIDHandler)
	app.Get("/api/wifi", getWifiInfoHandler)
	app.Get("/api/wifi-info", getWifiInfoHandler) // 别名路由
	app.Post("/api/folder/:folderId/sharing", updateFolderSharingHandler)

	// Syncthing 代理路由
	app.Get("/api/syncthing/events", syncthingEventsProxyHandler)

	// 健康检查端点
	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status":   "ok",
			"service":  "mydata-api",
			"platform": "desktop",
		})
	})

	fmt.Println("启动 API 服务在端口 8080...")
	if err := app.Listen(":8080"); err != nil {
		log.Printf("API 服务启动失败: %v", err)
	}
}
