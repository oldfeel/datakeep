package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"net"

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

// 提取 host（兼容 IPv4/IPv6）
func extractHost(addr string) string {
	parts := strings.SplitN(addr, "://", 2)
	if len(parts) != 2 {
		return ""
	}
	hostPort := parts[1]
	host, _, err := net.SplitHostPort(hostPort)
	if err != nil {
		// 兜底处理
		if strings.HasPrefix(hostPort, "[") {
			idx := strings.Index(hostPort, "]")
			if idx > 0 {
				return hostPort[1:idx]
			}
		}
		return strings.Split(hostPort, ":")[0]
	}
	return host
}

func syncEventsToDB() {
	logger.Info("启动后端主动轮询 Syncthing 事件并同步数据库")
	var lastEventID int
	apiKey := getApiKeyFromConfig()
	for {
		logger.Debug("准备请求 Syncthing 事件", zap.Int("lastEventID", lastEventID))
		// 构建 Syncthing 事件 API URL
		eventsURL := "http://127.0.0.1:8384/rest/events?since=" + fmt.Sprint(lastEventID) + "&timeout=30"
		req, err := http.NewRequest("GET", eventsURL, nil)
		if err != nil {
			logger.Error("创建事件请求失败", zap.Error(err))
			time.Sleep(5 * time.Second)
			continue
		}
		if apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}
		client := &http.Client{Timeout: 35 * time.Second}
		logger.Debug("开始请求 Syncthing 事件", zap.String("url", eventsURL))
		resp, err := client.Do(req)
		if err != nil {
			logger.Error("请求 Syncthing 事件失败", zap.Error(err), zap.String("url", eventsURL))
			time.Sleep(5 * time.Second)
			continue
		}
		logger.Debug("成功连接 Syncthing 事件接口", zap.String("url", eventsURL))
		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			logger.Error("读取事件响应失败", zap.Error(err))
			time.Sleep(5 * time.Second)
			continue
		}
		logger.Debug("成功读取事件响应", zap.Int("bodyLen", len(body)))
		var events []map[string]interface{}
		if err := json.Unmarshal(body, &events); err != nil {
			logger.Warn("事件内容无法解析为数组", zap.Error(err))
			time.Sleep(1 * time.Second)
			continue
		}
		logger.Debug("成功解析事件数组", zap.Int("eventCount", len(events)))
		for _, event := range events {
			id, _ := event["id"].(float64)
			if int(id) > lastEventID {
				lastEventID = int(id)
			}
			typeStr, _ := event["type"].(string)
			data, _ := event["data"].(map[string]interface{})
			switch typeStr {
			case "DeviceConnected":
				// 设备上线
				deviceID, _ := data["id"].(string)
				name, _ := data["deviceName"].(string)
				addr, _ := data["addr"].(string)
				if deviceID != "" {
					db.Where(DeviceInfo{DeviceID: deviceID}).Assign(DeviceInfo{
						Name:  name,
						LanIP: addr,
					}).FirstOrCreate(&DeviceInfo{})
					logger.Info("同步设备(DeviceConnected)", zap.String("deviceId", deviceID), zap.String("name", name), zap.String("lanIp", addr))
				}
			case "DeviceDiscovered":
				// 发现设备
				deviceID, _ := data["device"].(string)
				addrs, _ := data["addrs"].([]interface{})
				lanIp := ""
				for _, a := range addrs {
					if s, ok := a.(string); ok && len(s) > 0 && (strings.HasPrefix(s, "tcp") || strings.HasPrefix(s, "quic")) {
						host := extractHost(s)
						// 只保存 IPv4 地址
						if ip := net.ParseIP(host); ip != nil && ip.To4() != nil {
							lanIp = ip.String()
							break
						}
					}
				}
				if deviceID != "" && lanIp != "" {
					db.Where(DeviceInfo{DeviceID: deviceID}).Assign(DeviceInfo{
						LanIP: lanIp,
					}).FirstOrCreate(&DeviceInfo{})
					logger.Info("同步设备(DeviceDiscovered)", zap.String("deviceId", deviceID), zap.String("lanIp", lanIp))
				}
			case "FolderSummary":
				folderID, _ := data["folder"].(string)
				if folderID != "" {
					// 只同步文件夹ID，其他信息可后续补充
					db.Where(FolderInfo{FolderID: folderID}).FirstOrCreate(&FolderInfo{})
					logger.Info("同步文件夹(FolderSummary)", zap.String("folderId", folderID))
				}
			case "FolderCompletion":
				folderID, _ := data["folder"].(string)
				deviceID, _ := data["device"].(string)
				if folderID != "" && deviceID != "" {
					db.Where(FolderInfo{DeviceID: deviceID, FolderID: folderID}).FirstOrCreate(&FolderInfo{})
					logger.Info("同步文件夹(FolderCompletion)", zap.String("deviceId", deviceID), zap.String("folderId", folderID))
				}
			case "DeviceDisconnected":
				deviceID, _ := data["id"].(string)
				if deviceID != "" {
					// 这里可以将设备的 lan_ip 置空，或加 Online 字段置为 false
					db.Model(&DeviceInfo{}).Where("device_id = ?", deviceID).Update("lan_ip", "")
					logger.Info("同步设备(DeviceDisconnected)", zap.String("deviceId", deviceID))
				}
			}
		}
		logger.Debug("本轮事件处理完成，准备进入下一轮")
	}
}

func main() {
	logger = initZapLogger()
	logger.Info("zap + lumberjack 日志系统初始化完成")

	// 1. 初始化 GORM 数据库
	var err error
	db, err = gorm.Open(sqlite.Open("mydata.db"), &gorm.Config{})
	if err != nil {
		logger.Fatal("failed to connect database", zap.Error(err))
	}
	// 自动迁移设备表和文件夹表
	if err := db.AutoMigrate(&File{}, &DeviceInfo{}, &FolderInfo{}); err != nil {
		logger.Fatal("auto migrate failed", zap.Error(err))
	}

	// 2. 启动事件同步 goroutine
	go syncEventsToDB()

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
	app.Get("/api/syncthing/discovery", syncthingDiscoveryProxyHandler)           // 新增设备发现代理接口
	app.Get("/api/syncthing/deviceid", syncthingDeviceIdProxyHandler)             // 新增设备ID校验接口
	app.Post("/api/syncthing/config/devices", syncthingConfigDevicesProxyHandler) // 新增添加设备接口

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
