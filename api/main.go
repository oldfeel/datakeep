package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"path/filepath"

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

const (
	syncthingAPI = "http://127.0.0.1:8384/rest/config" // Syncthing REST API 地址
	apiKey       = "WkVAzozoXTJt4PWm9hj7xX5Ex2xkq3QN"  // 替换为你的 Syncthing API Key
)

func getFoldersFromSyncthing() ([]Folder, error) {
	req, err := http.NewRequest("GET", syncthingAPI, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-API-Key", apiKey)

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

func main() {
	app := fiber.New()

	// 静态文件服务（如有前端页面）
	app.Static("/", "./static")

	app.Get("/folders", foldersHandler)
	app.Get("/files", filesHandler)

	log.Println("Fiber API server started at :8080")
	log.Fatal(app.Listen(":8080"))
}
