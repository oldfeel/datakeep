package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type ConnectionInfo struct {
	Addresses     []string `json:"addresses"`
	Connected     bool     `json:"connected"`
	InBytesTotal  int64    `json:"inBytesTotal"`
	OutBytesTotal int64    `json:"outBytesTotal"`
	Type          string   `json:"type"`
	Address       string   `json:"address"`
	ClientVersion string   `json:"clientVersion"`
	IsLocal       bool     `json:"isLocal"`
	Crypto        string   `json:"crypto"`
	Primary       struct {
		Address string `json:"address"`
		Type    string `json:"type"`
	} `json:"primary"`
}

type DiscoveryInfo struct {
	Addresses []string `json:"addresses"`
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

func deviceFoldersHandler(c *fiber.Ctx) error {
	return success(c, folders)
}

func folderFilesHandler(c *fiber.Ctx) error {
	folderId := c.Params("folderId")
	path := c.Query("path", "")

	fmt.Printf("=== folderFilesHandler 开始 ===\n")
	fmt.Printf("folderId: %s\n", folderId)
	fmt.Printf("原始 path: %s\n", path)

	path = filepath.Clean(path)
	fmt.Printf("标准化后 path: %s\n", path)

	var files []File
	var err error
	if path == "" || path == "." {
		query := "%" + string(filepath.Separator) + "%"
		fmt.Printf("查询根目录，SQL条件: folder_id = %s AND path NOT LIKE %s\n", folderId, query)
		err = db.Where("folder_id = ? AND path NOT LIKE ?", folderId, query).Find(&files).Error
	} else {
		prefix := path + string(filepath.Separator)
		excludePattern := prefix + "%" + string(filepath.Separator) + "%" + string(filepath.Separator) + "%"
		fmt.Printf("查询子目录，SQL条件: folder_id = %s AND path LIKE %s AND path NOT LIKE %s\n", folderId, prefix+"%", excludePattern)
		err = db.Where("folder_id = ? AND path LIKE ? AND path NOT LIKE ?", folderId, prefix+"%", excludePattern).Find(&files).Error
	}

	if err != nil {
		fmt.Printf("数据库查询失败: %v\n", err)
		return fail(c, 1005, "数据库查询失败: "+err.Error())
	}

	fmt.Printf("查询结果数量: %d\n", len(files))
	if len(files) > 0 {
		fmt.Printf("前3个文件示例:\n")
		for i, file := range files {
			if i >= 3 {
				break
			}
			fmt.Printf("  - ID: %d, Path: %s, Name: %s, IsDir: %t\n", file.ID, file.Path, file.Name, file.IsDir)
		}
	} else {
		var totalCount int64
		db.Model(&File{}).Where("folder_id = ?", folderId).Count(&totalCount)
		fmt.Printf("该文件夹在数据库中的总文件数: %d\n", totalCount)
		var allFolders []File
		db.Select("DISTINCT folder_id").Find(&allFolders)
		fmt.Printf("数据库中的所有文件夹ID:\n")
		for _, f := range allFolders {
			fmt.Printf("  - %s\n", f.FolderID)
		}
		var sampleFiles []File
		db.Where("folder_id = ?", folderId).Limit(5).Find(&sampleFiles)
		fmt.Printf("该文件夹的前5个文件:\n")
		for _, file := range sampleFiles {
			fmt.Printf("  - ID: %d, Path: %s, Name: %s, IsDir: %t\n", file.ID, file.Path, file.Name, file.IsDir)
		}
	}

	fmt.Printf("=== folderFilesHandler 结束 ===\n")
	return success(c, files)
}

// Syncthing 相关 API 调用
func getDevicesFromSyncthing() ([]Device, error) {
	fmt.Printf("=== getDevicesFromSyncthing 开始 ===\n")

	// 获取设备配置
	fmt.Printf("正在调用 Syncthing API: GET /rest/config/devices\n")
	req, err := http.NewRequest("GET", "http://127.0.0.1:8384/rest/config/devices", nil)
	if err != nil {
		fmt.Printf("创建请求失败: %v\n", err)
		return nil, err
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())
	fmt.Printf("API Key: %s\n", getApiKeyFromConfig())

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("HTTP 请求失败: %v\n", err)
		return nil, err
	}
	defer resp.Body.Close()

	fmt.Printf("HTTP 响应状态码: %d\n", resp.StatusCode)
	if resp.StatusCode != 200 {
		fmt.Printf("Syncthing API 错误: %s\n", resp.Status)
		return nil, fmt.Errorf("syncthing api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("读取响应体失败: %v\n", err)
		return nil, err
	}
	fmt.Printf("响应体长度: %d 字节\n", len(body))

	var devices []Device
	if err := json.Unmarshal(body, &devices); err != nil {
		fmt.Printf("JSON 解析失败: %v\n", err)
		fmt.Printf("响应体内容: %s\n", string(body))
		return nil, err
	}
	fmt.Printf("成功解析到 %d 个设备:\n", len(devices))
	for i, device := range devices {
		fmt.Printf("  [%d] DeviceID: %s, Name: %s, Addresses: %v\n", i+1, device.DeviceID, device.Name, device.Addresses)
	}

	// 获取设备连接状态
	fmt.Printf("\n正在获取设备连接状态...\n")
	connections, err := getDeviceConnections()
	if err != nil {
		fmt.Printf("获取设备连接状态失败: %v\n", err)
		fmt.Printf("继续返回设备列表（不包含连接信息）\n")
		fmt.Printf("=== getDevicesFromSyncthing 结束 ===\n")
		return devices, nil
	}

	fmt.Printf("成功获取到 %d 个设备的连接信息:\n", len(connections))
	for deviceID, conn := range connections {
		fmt.Printf("  DeviceID: %s, Connected: %t, Type: %s, Address: %s, Primary Address: %s\n",
			deviceID, conn.Connected, conn.Type, conn.Address, conn.Primary.Address)
	}

	// 获取设备发现信息
	fmt.Printf("\n正在获取设备发现信息...\n")
	discoveryInfo, err := getDeviceDiscovery()
	if err != nil {
		fmt.Printf("获取设备发现信息失败: %v\n", err)
	} else {
		fmt.Printf("设备发现信息: %+v\n", discoveryInfo)
	}

	// 将连接信息和发现信息合并到设备信息中
	fmt.Printf("\n正在合并连接信息到设备列表...\n")
	for i, device := range devices {
		var addresses []string

		// 1. 从连接状态获取地址和连接信息
		if conn, exists := connections[device.DeviceID]; exists {
			devices[i].Connected = conn.Connected
			devices[i].ConnectionType = conn.Type
			devices[i].ClientVersion = conn.ClientVersion
			devices[i].InBytesTotal = conn.InBytesTotal
			devices[i].OutBytesTotal = conn.OutBytesTotal
			devices[i].IsLocal = conn.IsLocal
			devices[i].Crypto = conn.Crypto

			if conn.Connected && conn.Address != "" {
				addresses = append(addresses, conn.Address)
			}
			if conn.Connected && conn.Primary.Address != "" && conn.Primary.Address != conn.Address {
				addresses = append(addresses, conn.Primary.Address)
			}
		}

		// 2. 从设备发现信息获取地址
		if discoveryInfo != nil {
			if deviceAddrs, exists := discoveryInfo[device.DeviceID]; exists {
				if addrs, ok := deviceAddrs.(map[string]interface{}); ok {
					if addrList, ok := addrs["addresses"].([]interface{}); ok {
						for _, addr := range addrList {
							if addrStr, ok := addr.(string); ok {
								if !strings.Contains(addrStr, "relay://") {
									addresses = append(addresses, addrStr)
								}
							}
						}
					}
				}
			}
		}

		uniqueAddresses := make([]string, 0)
		seen := make(map[string]bool)
		for _, addr := range addresses {
			if !seen[addr] {
				seen[addr] = true
				uniqueAddresses = append(uniqueAddresses, addr)
			}
		}

		devices[i].Addresses = uniqueAddresses
		fmt.Printf("  设备 %s 更新地址: %v, 连接状态: %t, 类型: %s\n",
			device.Name, uniqueAddresses, devices[i].Connected, devices[i].ConnectionType)
	}

	fmt.Printf("=== getDevicesFromSyncthing 结束 ===\n")
	return devices, nil
}

func getDeviceConnections() (map[string]ConnectionInfo, error) {
	fmt.Printf("正在调用 Syncthing API: GET /rest/system/connections\n")
	req, err := http.NewRequest("GET", "http://127.0.0.1:8384/rest/system/connections", nil)
	if err != nil {
		fmt.Printf("创建连接状态请求失败: %v\n", err)
		return nil, err
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("连接状态 HTTP 请求失败: %v\n", err)
		return nil, err
	}
	defer resp.Body.Close()

	fmt.Printf("连接状态 HTTP 响应状态码: %d\n", resp.StatusCode)
	if resp.StatusCode != 200 {
		fmt.Printf("Syncthing 连接状态 API 错误: %s\n", resp.Status)
		return nil, fmt.Errorf("syncthing connections api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("读取连接状态响应体失败: %v\n", err)
		return nil, err
	}
	fmt.Printf("连接状态响应体长度: %d 字节\n", len(body))
	fmt.Printf("连接状态完整响应内容:\n%s\n", string(body))

	var connections struct {
		Connections map[string]ConnectionInfo `json:"connections"`
	}
	if err := json.Unmarshal(body, &connections); err != nil {
		fmt.Printf("连接状态 JSON 解析失败: %v\n", err)
		fmt.Printf("连接状态响应体内容: %s\n", string(body))
		return nil, err
	}

	fmt.Printf("成功解析连接状态，共 %d 个设备\n", len(connections.Connections))
	for deviceID, conn := range connections.Connections {
		fmt.Printf("设备 %s 详细连接信息:\n", deviceID)
		fmt.Printf("  - Connected: %t\n", conn.Connected)
		fmt.Printf("  - Type: %s\n", conn.Type)
		fmt.Printf("  - Addresses: %v\n", conn.Addresses)
		fmt.Printf("  - InBytesTotal: %d\n", conn.InBytesTotal)
		fmt.Printf("  - OutBytesTotal: %d\n", conn.OutBytesTotal)
	}

	return connections.Connections, nil
}

func getSystemStatus() (map[string]interface{}, error) {
	req, err := http.NewRequest("GET", "http://127.0.0.1:8384/rest/system/status", nil)
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
		return nil, fmt.Errorf("system status api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var status map[string]interface{}
	if err := json.Unmarshal(body, &status); err != nil {
		return nil, err
	}

	return status, nil
}

func getDeviceDiscovery() (map[string]interface{}, error) {
	req, err := http.NewRequest("GET", "http://127.0.0.1:8384/rest/system/discovery", nil)
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
		return nil, fmt.Errorf("device discovery api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var discovery map[string]interface{}
	if err := json.Unmarshal(body, &discovery); err != nil {
		return nil, err
	}

	return discovery, nil
}
