package backend

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"time"

	"encoding/json"
	"io"
	"net/http"
	"strings"

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

// ensureCert 检查并自动生成自签名证书
func ensureCert(certFile, keyFile string) error {
	if _, err := os.Stat(certFile); err == nil {
		if _, err := os.Stat(keyFile); err == nil {
			return nil // 都存在
		}
	}

	logger.Info("生成自签名证书", zap.String("certFile", certFile), zap.String("keyFile", keyFile))

	// 生成自签名证书
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return err
	}
	template := x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "localhost"},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().Add(10 * 365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              []string{"localhost", "127.0.0.1"},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")},
	}
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		return err
	}
	certOut, err := os.Create(certFile)
	if err != nil {
		return err
	}
	defer certOut.Close()
	pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	keyOut, err := os.Create(keyFile)
	if err != nil {
		return err
	}
	defer keyOut.Close()
	pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	logger.Info("自签名证书生成完成")
	return nil
}

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

	// 同时输出到控制台和文件
	consoleCore := zapcore.NewCore(encoder, zapcore.AddSync(os.Stdout), zapcore.DebugLevel)
	fileCore := zapcore.NewCore(encoder, zapcore.AddSync(ljWriter), zapcore.DebugLevel)
	core := zapcore.NewTee(consoleCore, fileCore) // 使用 Tee 同时写入多个目标

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
		eventsURL := "https://127.0.0.1:8384/rest/events?since=" + fmt.Sprint(lastEventID) + "&timeout=30"
		req, err := http.NewRequest("GET", eventsURL, nil)
		if err != nil {
			logger.Error("创建事件请求失败", zap.Error(err))
			time.Sleep(5 * time.Second)
			continue
		}
		if apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}
		// 创建 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
		tr := &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}
		client := &http.Client{Transport: tr, Timeout: 35 * time.Second}
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

func StartServer() {
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

	// 获取 config.xml 路径
	configPath = getConfigPath()
	logger.Info("Syncthing config.xml", zap.String("path", configPath))

	// 异步启动索引
	logger.Info("启动异步索引...")
	go func() {
		loadAndIndex()
	}()

	// 监听 config.xml 变化
	go watchConfig()

	// 5. 启动 Fiber API 服务
	app := fiber.New(fiber.Config{
		AppName:      "MyData API Server",
		ServerHeader: "MyData",
		// 性能优化配置
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
		// 连接池配置
		DisableStartupMessage: true,
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}
			return c.Status(code).JSON(fiber.Map{
				"code": code,
				"data": err.Error(),
			})
		},
	})

	// 添加中间件来检测请求来源
	app.Use(func(c *fiber.Ctx) error {
		// 检测是否为本地请求
		clientIP := c.IP()
		userAgent := c.Get("User-Agent", "")
		referer := c.Get("Referer", "")
		origin := c.Get("Origin", "")

		// 判断是否为本地请求
		isLocalRequest := clientIP == "127.0.0.1" ||
			clientIP == "localhost" ||
			clientIP == "::1" ||
			strings.Contains(userAgent, "Wails") ||
			strings.Contains(referer, "wails.localhost") ||
			strings.Contains(origin, "wails.localhost")

		// 将判断结果存储在上下文中
		c.Locals("isLocalRequest", isLocalRequest)
		c.Locals("clientIP", clientIP)
		c.Locals("userAgent", userAgent)

		logger.Info("请求来源检测",
			zap.String("path", c.Path()),
			zap.String("clientIP", clientIP),
			zap.String("userAgent", userAgent),
			zap.Bool("isLocalRequest", isLocalRequest),
		)

		return c.Next()
	})

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
	app.Get("/api/syncthing/discovery", syncthingDiscoveryProxyHandler)
	app.Get("/api/syncthing/deviceid", syncthingDeviceIdProxyHandler)
	app.Post("/api/syncthing/config/devices", syncthingConfigDevicesProxyHandler)

	// 健康检查端点
	app.Get("/health", func(c *fiber.Ctx) error {
		isLocal := c.Locals("isLocalRequest").(bool)
		clientIP := c.Locals("clientIP").(string)

		return c.JSON(fiber.Map{
			"status":   "ok",
			"service":  "mydata-api",
			"platform": "desktop",
			"isLocal":  isLocal,
			"clientIP": clientIP,
			"protocol": c.Protocol(),
			"port":     c.Port(),
		})
	})

	// 自动生成证书
	certFile := filepath.Join("certs", "cert.pem")
	keyFile := filepath.Join("certs", "key.pem")

	// 创建证书目录
	if err := os.MkdirAll("certs", 0755); err != nil {
		logger.Fatal("创建证书目录失败", zap.Error(err))
	}

	if err := ensureCert(certFile, keyFile); err != nil {
		logger.Fatal("自动生成证书失败", zap.Error(err))
	}

	// 启动 HTTPS 服务（用于本机和局域网访问）
	logger.Info("启动 HTTPS API 服务", zap.String("port", "8443"))
	logger.Info("HTTPS 服务器地址", zap.String("url", "https://localhost:8443"))
	logger.Info("用途: 本机和局域网设备访问（Android 需要 HTTPS）")
	logger.Info("")
	logger.Info("可用的 API 端点:")
	logger.Info("  - GET    /api/folder/:folderId")
	logger.Info("  - GET    /api/devices")
	logger.Info("  - GET    /api/device/:deviceId/folders")
	logger.Info("  - GET    /api/deviceid")
	logger.Info("  - GET    /api/wifi")
	logger.Info("  - GET    /health")
	logger.Info("")
	logger.Info("服务配置:")
	logger.Info("  - HTTPS: https://localhost:8443")

	if err := app.ListenTLS(":8443", certFile, keyFile); err != nil {
		logger.Fatal("HTTPS API 服务启动失败", zap.Error(err))
	}
}
