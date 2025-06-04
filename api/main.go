package main

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"

	"github.com/gofiber/fiber/v2"
)

type Folder struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Path  string `json:"path"`
}

type SyncthingConfig struct {
	Folders []Folder `json:"folders"`
}

type Device struct {
	DeviceID    string   `json:"deviceID"`
	Name        string   `json:"name"`
	Addresses   []string `json:"addresses"`
	Compression string   `json:"compression"`
	CertName    string   `json:"certName"`
	Introducer  bool     `json:"introducer"`
}

type DevicesConfig struct {
	Devices []Device `json:"devices"`
}

const (
	syncthingAPI = "http://127.0.0.1:8384/rest/config" // Syncthing REST API 地址
	apiKey       = ""                                  // 替换为你的 Syncthing API Key
)

func getConfigPath() string {
	if runtime.GOOS == "android" {
		return "/data/data/com.nutomic.syncthingandroid/files/config.xml"
	}
	home, err := os.UserHomeDir()
	if err != nil {
		home = "~" // fallback
	}
	switch runtime.GOOS {
	case "windows":
		return home + `\\AppData\\Local\\Syncthing\\config.xml`
	case "darwin":
		return home + "/Library/Application Support/Syncthing/config.xml"
	default: // linux, etc.
		return home + "/.config/syncthing/config.xml"
	}
}

// 解析 config.xml 获取 apikey
func getApiKeyFromConfig() string {
	configPath := getConfigPath()
	type Gui struct {
		APIKey string `xml:"apikey"`
	}
	type Config struct {
		Gui Gui `xml:"gui"`
	}
	data, err := ioutil.ReadFile(configPath)
	if err != nil {
		return apiKey // 失败时用常量
	}
	var cfg Config
	err = xml.Unmarshal(data, &cfg)
	if err != nil || cfg.Gui.APIKey == "" {
		return apiKey
	}
	return cfg.Gui.APIKey
}

func getFoldersFromSyncthing() ([]Folder, error) {
	req, err := http.NewRequest("GET", syncthingAPI, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("syncthing api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var config SyncthingConfig
	if err := json.Unmarshal(body, &config); err != nil {
		return nil, err
	}
	return config.Folders, nil
}

func getDevicesFromSyncthing() ([]Device, error) {
	req, err := http.NewRequest("GET", "http://127.0.0.1:8384/rest/config/devices", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("syncthing api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var config DevicesConfig
	if err := json.Unmarshal(body, &config); err != nil {
		return nil, err
	}
	return config.Devices, nil
}

func success(c *fiber.Ctx, data interface{}) error {
	return c.JSON(fiber.Map{
		"code": 0,
		"data": data,
	})
}

func fail(c *fiber.Ctx, code int, msg string) error {
	return c.JSON(fiber.Map{
		"code": code,
		"data": msg,
	})
}

func foldersHandler(c *fiber.Ctx) error {
	folders, err := getFoldersFromSyncthing()
	if err != nil {
		return fail(c, 1001, "Failed to get folders: "+err.Error())
	}
	return success(c, folders)
}

// /files?path=/storage/emulated/0/Syncthing
func filesHandler(c *fiber.Ctx) error {
	path := c.Query("path")
	if path == "" {
		return fail(c, 1002, "Missing path param")
	}
	files, err := ioutil.ReadDir(path)
	if err != nil {
		return fail(c, 1003, "Failed to read dir: "+err.Error())
	}
	var result []fiber.Map
	for _, f := range files {
		result = append(result, fiber.Map{
			"name":    f.Name(),
			"isDir":   f.IsDir(),
			"size":    f.Size(),
			"modTime": f.ModTime(),
			"absPath": filepath.Join(path, f.Name()),
		})
	}
	return success(c, result)
}

func devicesHandler(c *fiber.Ctx) error {
	devices, err := getDevicesFromSyncthing()
	if err != nil {
		return fail(c, 1004, "Failed to get devices: "+err.Error())
	}
	return success(c, devices)
}

// GetDevices 返回所有设备列表
func GetDevices() ([]Device, error) {
	return getDevicesFromSyncthing()
}

func main() {
	app := fiber.New()

	// 静态文件服务（如有前端页面）
	app.Static("/", "./static")

	app.Get("/folders", foldersHandler)
	app.Get("/files", filesHandler)
	app.Get("/devices", devicesHandler)

	log.Println("Fiber API server started at :8080")
	log.Fatal(app.Listen(":8080"))
}
