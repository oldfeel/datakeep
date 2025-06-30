package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net"
	"net/http"
	"net/url"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type ConnectionInfo struct {
	Addresses      []string `json:"addresses"`
	Connected      bool     `json:"connected"`
	InBytesTotal   int64    `json:"inBytesTotal"`
	OutBytesTotal  int64    `json:"outBytesTotal"`
	Type           string   `json:"type"`
	Address        string   `json:"address"`
	ClientVersion  string   `json:"clientVersion"`
	IsLocalNetwork bool     `json:"isLocalNetwork"`
	Crypto         string   `json:"crypto"`
	Primary        struct {
		Address string `json:"address"`
		Type    string `json:"type"`
	} `json:"primary"`
}

type DiscoveryInfo struct {
	Addresses []string `json:"addresses"`
}

// 获取本机局域网IP地址
func getLocalNetworkIPs() ([]string, error) {
	var localIPs []string

	// 获取所有网络接口
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}

	for _, iface := range interfaces {
		// 跳过回环接口和down的接口
		if iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagUp == 0 {
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}

		for _, addr := range addrs {
			switch v := addr.(type) {
			case *net.IPNet:
				// 只获取IPv4地址，并且是私有地址
				if v.IP.To4() != nil && isPrivateIP(v.IP) {
					localIPs = append(localIPs, v.IP.String())
				}
			}
		}
	}

	return localIPs, nil
}

// 判断是否为私有IP地址
func isPrivateIP(ip net.IP) bool {
	// 私有IP地址范围
	privateRanges := []struct {
		start net.IP
		end   net.IP
	}{
		{net.ParseIP("10.0.0.0"), net.ParseIP("10.255.255.255")},     // 10.0.0.0/8
		{net.ParseIP("172.16.0.0"), net.ParseIP("172.31.255.255")},   // 172.16.0.0/12
		{net.ParseIP("192.168.0.0"), net.ParseIP("192.168.255.255")}, // 192.168.0.0/16
	}

	for _, r := range privateRanges {
		if bytes2Int(ip) >= bytes2Int(r.start) && bytes2Int(ip) <= bytes2Int(r.end) {
			return true
		}
	}
	return false
}

// 将IP地址转换为整数进行比较
func bytes2Int(ip net.IP) uint32 {
	ip = ip.To4()
	return uint32(ip[0])<<24 + uint32(ip[1])<<16 + uint32(ip[2])<<8 + uint32(ip[3])
}

// 从地址字符串中提取IP地址
func extractIPFromAddress(addr string) string {
	// 匹配IPv4地址的正则表达式
	ipv4Regex := regexp.MustCompile(`(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})`)
	matches := ipv4Regex.FindStringSubmatch(addr)
	if len(matches) > 1 {
		return matches[1]
	}
	return ""
}

// 过滤地址，只保留IP地址（不包含协议和端口），并且去重
func filterAndExtractIPAddresses(addresses []string) []string {
	localIPs, err := getLocalNetworkIPs()
	if err != nil {
		fmt.Printf("获取本机局域网IP失败: %v，返回原始地址列表\n", err)
		return []string{}
	}

	fmt.Printf("本机局域网IP: %v\n", localIPs)

	// 用于去重的map
	uniqueIPs := make(map[string]bool)
	var filteredIPs []string

	for _, addr := range addresses {
		fmt.Printf("  检查地址: %s\n", addr)

		// 跳过relay地址
		if strings.Contains(addr, "relay://") {
			fmt.Printf("    跳过relay地址: %s\n", addr)
			continue
		}

		// 跳过IPv6地址（暂时）
		if strings.Contains(addr, "[") && strings.Contains(addr, "]") {
			fmt.Printf("    跳过IPv6地址: %s\n", addr)
			continue
		}

		// 提取IP地址
		ip := extractIPFromAddress(addr)
		if ip == "" {
			fmt.Printf("    无法提取IP地址: %s\n", addr)
			continue
		}

		fmt.Printf("    提取到IP: %s\n", ip)

		// 检查是否与本机在同一局域网
		if isInSameNetwork(ip, localIPs) {
			// 如果IP还没有被添加过，则添加
			if !uniqueIPs[ip] {
				fmt.Printf("    添加新IP(同网段): %s\n", ip)
				uniqueIPs[ip] = true
				filteredIPs = append(filteredIPs, ip)
			} else {
				fmt.Printf("    跳过重复IP: %s\n", ip)
			}
		} else {
			fmt.Printf("    过滤IP(不同网段): %s\n", ip)
		}
	}

	fmt.Printf("过滤前地址数量: %d, 过滤后IP数量: %d\n", len(addresses), len(filteredIPs))
	// 确保返回空数组而不是 nil
	if filteredIPs == nil {
		filteredIPs = []string{}
	}
	return filteredIPs
}

// 检查IP是否与本机在同一局域网
func isInSameNetwork(ip string, localIPs []string) bool {
	ipAddr := net.ParseIP(ip)
	if ipAddr == nil {
		fmt.Printf("      无法解析IP: %s\n", ip)
		return false
	}

	for _, localIP := range localIPs {
		localAddr := net.ParseIP(localIP)
		if localAddr == nil {
			continue
		}

		fmt.Printf("      比较IP: %s 与本地IP: %s\n", ip, localIP)

		// 检查是否在同一网段（前三个字节相同）
		if ipAddr.To4() != nil && localAddr.To4() != nil {
			ipBytes := ipAddr.To4()
			localBytes := localAddr.To4()

			// 对于192.168.x.x，检查前两个字节
			if ipBytes[0] == 192 && ipBytes[1] == 168 &&
				localBytes[0] == 192 && localBytes[1] == 168 {
				if ipBytes[2] == localBytes[2] {
					fmt.Printf("        192.168.x.x 网段匹配: %d.%d.%d.x\n", ipBytes[0], ipBytes[1], ipBytes[2])
					return true
				} else {
					fmt.Printf("        192.168.x.x 网段不匹配: %d.%d.%d.x vs %d.%d.%d.x\n",
						ipBytes[0], ipBytes[1], ipBytes[2], localBytes[0], localBytes[1], localBytes[2])
				}
			}

			// 对于10.x.x.x，检查第一个字节
			if ipBytes[0] == 10 && localBytes[0] == 10 {
				fmt.Printf("        10.x.x.x 网段匹配\n")
				return true
			}

			// 对于172.16-31.x.x，检查前两个字节
			if ipBytes[0] == 172 && localBytes[0] == 172 {
				if ipBytes[1] >= 16 && ipBytes[1] <= 31 &&
					localBytes[1] >= 16 && localBytes[1] <= 31 {
					fmt.Printf("        172.16-31.x.x 网段匹配: %d.%d.x.x\n", ipBytes[0], ipBytes[1])
					return true
				}
			}
		}
	}

	fmt.Printf("      不在同一网段\n")
	return false
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
	// 根据 HTTP 方法处理不同的操作
	switch c.Method() {
	case "GET":
		return success(c, folders)
	case "POST":
		return addFolderHandler(c)
	case "PUT":
		return updateFolderHandler(c)
	case "DELETE":
		return deleteFolderHandler(c)
	default:
		return fail(c, 405, "Method not allowed")
	}
}

// 添加文件夹处理器
func addFolderHandler(c *fiber.Ctx) error {
	// 解析请求体
	var newFolder FolderEntry
	if err := c.BodyParser(&newFolder); err != nil {
		return fail(c, 1001, "Invalid request body: "+err.Error())
	}

	// 验证必填字段
	if newFolder.ID == "" {
		return fail(c, 1002, "Folder ID is required")
	}
	if newFolder.Path == "" {
		return fail(c, 1002, "Folder path is required")
	}

	// 检查文件夹 ID 是否已存在
	for _, folder := range folders {
		if folder.ID == newFolder.ID {
			return fail(c, 1003, "Folder ID already exists")
		}
	}

	// 调用 syncthing API 创建文件夹
	if err := createSyncthingFolder(newFolder); err != nil {
		return fail(c, 1004, "Failed to create folder in syncthing: "+err.Error())
	}

	// 添加新文件夹到内存中的列表
	mu.Lock()
	folders = append(folders, newFolder)
	mu.Unlock()

	fmt.Printf("成功创建新文件夹: ID=%s, Label=%s, Path=%s\n", newFolder.ID, newFolder.Label, newFolder.Path)

	return success(c, map[string]interface{}{
		"message": "Folder created successfully",
		"folder":  newFolder,
	})
}

// 调用 syncthing API 创建文件夹
func createSyncthingFolder(folder FolderEntry) error {
	// 构建 syncthing 文件夹配置，包含设备共享信息
	folderConfig := map[string]interface{}{
		"id":    folder.ID,
		"label": folder.Label,
		"path":  folder.Path,
		"type":  "sendreceive",
	}

	// 如果有共享设备，添加到配置中
	if len(folder.SharedDevices) > 0 {
		devices := make([]map[string]interface{}, 0, len(folder.SharedDevices))
		for _, deviceID := range folder.SharedDevices {
			devices = append(devices, map[string]interface{}{
				"deviceID": deviceID,
			})
		}
		folderConfig["devices"] = devices
	}

	// 序列化为 JSON
	jsonData, err := json.Marshal(folderConfig)
	if err != nil {
		return fmt.Errorf("failed to marshal folder config: %v", err)
	}

	// 构建 syncthing API URL
	syncthingURL := "http://127.0.0.1:8384/rest/config/folders"

	// 创建请求
	req, err := http.NewRequest("POST", syncthingURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create request: %v", err)
	}

	// 设置请求头
	req.Header.Set("Content-Type", "application/json")

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request to syncthing: %v", err)
	}
	defer resp.Body.Close()

	// 检查响应状态
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("syncthing API returned status %d: %s", resp.StatusCode, string(body))
	}

	fmt.Printf("成功调用 syncthing API 创建文件夹: %s\n", folder.ID)
	return nil
}

// 更新文件夹处理器
func updateFolderHandler(c *fiber.Ctx) error {
	folderID := c.Params("folderId")

	// 解析请求体
	var updatedFolder FolderEntry
	if err := c.BodyParser(&updatedFolder); err != nil {
		return fail(c, 1001, "Invalid request body: "+err.Error())
	}

	// 验证必填字段
	if updatedFolder.ID == "" {
		return fail(c, 1002, "Folder ID is required")
	}
	if updatedFolder.Path == "" {
		return fail(c, 1002, "Folder path is required")
	}

	// 查找并更新文件夹
	var found bool
	mu.Lock()
	for i := range folders {
		if folders[i].ID == folderID {
			// 更新文件夹信息
			folders[i].Label = updatedFolder.Label
			folders[i].Path = updatedFolder.Path
			folders[i].SharedDevices = updatedFolder.SharedDevices
			found = true
			break
		}
	}
	mu.Unlock()

	if !found {
		return fail(c, 1002, "Folder not found")
	}

	// 调用 syncthing API 更新文件夹配置
	if err := updateSyncthingFolder(folderID, updatedFolder); err != nil {
		return fail(c, 1004, "Failed to update folder in syncthing: "+err.Error())
	}

	fmt.Printf("成功更新文件夹: ID=%s, Label=%s, Path=%s\n", updatedFolder.ID, updatedFolder.Label, updatedFolder.Path)

	return success(c, map[string]interface{}{
		"message": "Folder updated successfully",
		"folder":  updatedFolder,
	})
}

// 调用 syncthing API 更新文件夹
func updateSyncthingFolder(folderID string, folder FolderEntry) error {
	// 1. 获取当前文件夹完整配置
	syncthingURL := fmt.Sprintf("http://127.0.0.1:8384/rest/config/folders/%s", folderID)
	req, err := http.NewRequest("GET", syncthingURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create GET request: %v", err)
	}
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to GET folder config: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("GET syncthing folder config failed: %s", string(body))
	}
	var folderConfig map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&folderConfig); err != nil {
		return fmt.Errorf("failed to decode folder config: %v", err)
	}

	// 2. 更新配置字段
	folderConfig["label"] = folder.Label
	folderConfig["path"] = folder.Path

	// 更新设备共享
	if len(folder.SharedDevices) > 0 {
		devices := make([]map[string]interface{}, 0, len(folder.SharedDevices))
		for _, deviceID := range folder.SharedDevices {
			devices = append(devices, map[string]interface{}{
				"deviceID": deviceID,
			})
		}
		folderConfig["devices"] = devices
	}

	// 3. PUT 回去
	jsonData, err := json.Marshal(folderConfig)
	if err != nil {
		return fmt.Errorf("failed to marshal updated config: %v", err)
	}
	putReq, err := http.NewRequest("PUT", syncthingURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create PUT request: %v", err)
	}
	putReq.Header.Set("Content-Type", "application/json")
	if apiKey != "" {
		putReq.Header.Set("X-API-Key", apiKey)
	}
	putResp, err := client.Do(putReq)
	if err != nil {
		return fmt.Errorf("failed to PUT updated config: %v", err)
	}
	defer putResp.Body.Close()
	if putResp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(putResp.Body)
		return fmt.Errorf("PUT syncthing folder config failed: %s", string(body))
	}
	return nil
}

// 更新文件夹共享配置的处理函数
func updateFolderSharingHandler(c *fiber.Ctx) error {
	folderID := c.Params("folderId")

	// 解析请求体
	var request struct {
		SharedDevices []string `json:"sharedDevices"`
	}
	if err := c.BodyParser(&request); err != nil {
		return fail(c, 1001, "Invalid request body: "+err.Error())
	}

	// 查找文件夹
	var targetFolder *FolderEntry
	mu.Lock()
	for i := range folders {
		if folders[i].ID == folderID {
			targetFolder = &folders[i]
			break
		}
	}
	mu.Unlock()

	if targetFolder == nil {
		return fail(c, 1002, "Folder not found")
	}

	// 调用 syncthing API 更新文件夹配置
	if err := updateSyncthingFolderSharing(folderID, request.SharedDevices); err != nil {
		return fail(c, 1004, "Failed to update folder sharing in syncthing: "+err.Error())
	}

	// 更新本地配置
	mu.Lock()
	targetFolder.SharedDevices = request.SharedDevices
	mu.Unlock()

	fmt.Printf("成功更新文件夹共享配置: ID=%s, 共享设备=%v\n", folderID, request.SharedDevices)

	return success(c, map[string]interface{}{
		"message": "Folder sharing updated successfully",
		"folder":  targetFolder,
	})
}

// 调用 syncthing API 更新文件夹共享配置
func updateSyncthingFolderSharing(folderID string, sharedDevices []string) error {
	// 1. 获取当前文件夹完整配置
	syncthingURL := fmt.Sprintf("http://127.0.0.1:8384/rest/config/folders/%s", folderID)
	req, err := http.NewRequest("GET", syncthingURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create GET request: %v", err)
	}
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to GET folder config: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("GET syncthing folder config failed: %s", string(body))
	}
	var folderConfig map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&folderConfig); err != nil {
		return fmt.Errorf("failed to decode folder config: %v", err)
	}

	// 2. 获取本机设备ID
	localDeviceID, err := getLocalDeviceID()
	if err != nil {
		return fmt.Errorf("failed to get local device ID: %v", err)
	}

	// 3. 构建新的 devices 数组
	// 首先保留本机设备（如果存在）
	var devices []map[string]interface{}

	// 检查当前配置中是否有本机设备
	if currentDevices, ok := folderConfig["devices"].([]interface{}); ok {
		for _, device := range currentDevices {
			if deviceMap, ok := device.(map[string]interface{}); ok {
				if deviceID, ok := deviceMap["deviceID"].(string); ok && deviceID == localDeviceID {
					// 保留本机设备
					devices = append(devices, deviceMap)
					break
				}
			}
		}
	}

	// 添加要共享的设备
	for _, deviceID := range sharedDevices {
		if deviceID != localDeviceID { // 避免重复添加本机设备
			devices = append(devices, map[string]interface{}{
				"deviceID": deviceID,
			})
		}
	}

	folderConfig["devices"] = devices

	// 4. PUT 回去
	jsonData, err := json.Marshal(folderConfig)
	if err != nil {
		return fmt.Errorf("failed to marshal updated config: %v", err)
	}
	putReq, err := http.NewRequest("PUT", syncthingURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create PUT request: %v", err)
	}
	putReq.Header.Set("Content-Type", "application/json")
	if apiKey != "" {
		putReq.Header.Set("X-API-Key", apiKey)
	}
	putResp, err := client.Do(putReq)
	if err != nil {
		return fmt.Errorf("failed to PUT updated config: %v", err)
	}
	defer putResp.Body.Close()
	if putResp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(putResp.Body)
		return fmt.Errorf("PUT syncthing folder config failed: %s", string(body))
	}
	return nil
}

func folderFilesHandler(c *fiber.Ctx) error {
	folderId := c.Params("folderId")
	path := c.Query("path", "")

	// URL解码folderId，处理中文字符
	decodedFolderId, err := url.QueryUnescape(folderId)
	if err != nil {
		fmt.Printf("URL解码失败: %v\n", err)
		decodedFolderId = folderId // 解码失败时使用原始值
	}

	fmt.Printf("=== folderFilesHandler 开始 ===\n")
	fmt.Printf("原始 folderId: %s\n", folderId)
	fmt.Printf("解码后 folderId: %s\n", decodedFolderId)
	fmt.Printf("原始 path: %s\n", path)

	path = filepath.Clean(path)
	fmt.Printf("标准化后 path: %s\n", path)

	var files []File
	if path == "" || path == "." {
		query := "%" + string(filepath.Separator) + "%"
		fmt.Printf("查询根目录，SQL条件: folder_id = %s AND path NOT LIKE %s\n", decodedFolderId, query)
		err = db.Where("folder_id = ? AND path NOT LIKE ?", decodedFolderId, query).Find(&files).Error
	} else {
		prefix := path + string(filepath.Separator)
		excludePattern := prefix + "%" + string(filepath.Separator) + "%" + string(filepath.Separator) + "%"
		fmt.Printf("查询子目录，SQL条件: folder_id = %s AND path LIKE %s AND path NOT LIKE %s\n", decodedFolderId, prefix+"%", excludePattern)
		err = db.Where("folder_id = ? AND path LIKE ? AND path NOT LIKE ?", decodedFolderId, prefix+"%", excludePattern).Find(&files).Error
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
		db.Model(&File{}).Where("folder_id = ?", decodedFolderId).Count(&totalCount)
		fmt.Printf("该文件夹在数据库中的总文件数: %d\n", totalCount)
		var allFolders []File
		db.Select("DISTINCT folder_id").Find(&allFolders)
		fmt.Printf("数据库中的所有文件夹ID:\n")
		for _, f := range allFolders {
			fmt.Printf("  - %s\n", f.FolderID)
		}
		var sampleFiles []File
		db.Where("folder_id = ?", decodedFolderId).Limit(5).Find(&sampleFiles)
		fmt.Printf("该文件夹的前5个文件:\n")
		for _, file := range sampleFiles {
			fmt.Printf("  - ID: %d, Path: %s, Name: %s, IsDir: %t\n", file.ID, file.Path, file.Name, file.IsDir)
		}
	}

	fmt.Printf("=== folderFilesHandler 结束 ===\n")
	return success(c, files)
}

// 代理 syncthing 事件接口，解决跨域问题
func syncthingEventsProxyHandler(c *fiber.Ctx) error {
	// 获取查询参数
	since := c.Query("since", "0")
	timeout := c.Query("timeout", "60")
	limit := c.Query("limit", "")
	events := c.Query("events", "")

	// 构建 syncthing API URL
	syncthingURL := "http://127.0.0.1:8384/rest/events"
	params := url.Values{}
	params.Set("since", since)
	params.Set("timeout", timeout)
	if limit != "" {
		params.Set("limit", limit)
	}
	if events != "" {
		params.Set("events", events)
	}

	if len(params) > 0 {
		syncthingURL += "?" + params.Encode()
	}

	// 创建请求
	req, err := http.NewRequest("GET", syncthingURL, nil)
	if err != nil {
		return fail(c, 1005, "Failed to create request: "+err.Error())
	}

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fail(c, 1006, "Failed to request syncthing: "+err.Error())
	}
	defer resp.Body.Close()

	// 读取响应
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fail(c, 1007, "Failed to read response: "+err.Error())
	}

	// 设置响应头
	c.Set("Content-Type", "application/json")
	c.Status(resp.StatusCode)

	// 返回响应
	return c.Send(body)
}

// 代理 syncthing 设备发现接口，解决跨域问题
func syncthingDiscoveryProxyHandler(c *fiber.Ctx) error {
	// 构建 syncthing API URL
	syncthingURL := "http://127.0.0.1:8384/rest/system/discovery"

	// 创建请求
	req, err := http.NewRequest("GET", syncthingURL, nil)
	if err != nil {
		return fail(c, 1005, "Failed to create request: "+err.Error())
	}

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fail(c, 1006, "Failed to request syncthing: "+err.Error())
	}
	defer resp.Body.Close()

	// 读取响应
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fail(c, 1007, "Failed to read response: "+err.Error())
	}

	// 设置响应头
	c.Set("Content-Type", "application/json")
	c.Status(resp.StatusCode)

	// 返回响应
	return c.Send(body)
}

// 代理 syncthing 设备 ID 验证接口，解决跨域问题
func syncthingDeviceIdProxyHandler(c *fiber.Ctx) error {
	// 获取查询参数
	id := c.Query("id")
	if id == "" {
		return fail(c, 1002, "Missing id parameter")
	}

	// 构建 syncthing API URL
	syncthingURL := fmt.Sprintf("http://127.0.0.1:8384/rest/svc/deviceid?id=%s", url.QueryEscape(id))

	// 创建请求
	req, err := http.NewRequest("GET", syncthingURL, nil)
	if err != nil {
		return fail(c, 1005, "Failed to create request: "+err.Error())
	}

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fail(c, 1006, "Failed to request syncthing: "+err.Error())
	}
	defer resp.Body.Close()

	// 读取响应
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fail(c, 1007, "Failed to read response: "+err.Error())
	}

	// 设置响应头
	c.Set("Content-Type", "application/json")
	c.Status(resp.StatusCode)

	// 返回响应
	return c.Send(body)
}

// 代理 syncthing 设备配置接口（支持 GET 和 POST），解决跨域问题
func syncthingConfigDevicesProxyHandler(c *fiber.Ctx) error {
	// 构建 syncthing API URL
	syncthingURL := "http://127.0.0.1:8384/rest/config/devices"

	// 获取请求方法和请求体
	method := c.Method()
	var body io.Reader
	if method == "POST" {
		body = bytes.NewReader(c.Body())
	}

	// 创建请求
	req, err := http.NewRequest(method, syncthingURL, body)
	if err != nil {
		return fail(c, 1005, "Failed to create request: "+err.Error())
	}

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// 复制请求头
	if method == "POST" {
		req.Header.Set("Content-Type", "application/json")
	}

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fail(c, 1006, "Failed to request syncthing: "+err.Error())
	}
	defer resp.Body.Close()

	// 读取响应
	respBody, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fail(c, 1007, "Failed to read response: "+err.Error())
	}

	// 设置响应头
	c.Set("Content-Type", "application/json")
	c.Status(resp.StatusCode)

	// 返回响应
	return c.Send(respBody)
}

// Syncthing 相关 API 调用
func getDevicesFromSyncthing() ([]Device, error) {
	fmt.Printf("=== getDevicesFromSyncthing 开始 ===\n")

	// 获取设备配置
	fmt.Printf("正在调用 Syncthing API: GET /rest/config/devices\n")
	req, err := http.NewRequest("GET", "https://127.0.0.1:8384/rest/config/devices", nil)
	if err != nil {
		fmt.Printf("创建请求失败: %v\n", err)
		return nil, err
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())
	fmt.Printf("API Key: %s\n", getApiKeyFromConfig())

	// 创建跳过证书验证的 HTTP 客户端
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

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
			devices[i].IsLocalNetwork = conn.IsLocalNetwork
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

		// 应用局域网地址过滤
		filteredAddresses := filterAndExtractIPAddresses(uniqueAddresses)
		// 确保 addresses 始终是一个数组而不是 nil
		if filteredAddresses == nil {
			filteredAddresses = []string{}
		}
		devices[i].Addresses = filteredAddresses
		fmt.Printf("  设备 %s 更新地址: %v, 连接状态: %t, 类型: %s, 本地连接: %t\n",
			device.Name, filteredAddresses, devices[i].Connected, devices[i].ConnectionType, devices[i].IsLocalNetwork)
	}

	fmt.Printf("=== getDevicesFromSyncthing 结束 ===\n")
	return devices, nil
}

func getDeviceConnections() (map[string]ConnectionInfo, error) {
	fmt.Printf("正在调用 Syncthing API: GET /rest/system/connections\n")
	req, err := http.NewRequest("GET", "https://127.0.0.1:8384/rest/system/connections", nil)
	if err != nil {
		fmt.Printf("创建连接状态请求失败: %v\n", err)
		return nil, err
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	// 创建跳过证书验证的 HTTP 客户端
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

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

// 删除文件夹处理器
func deleteFolderHandler(c *fiber.Ctx) error {
	// 从 URL 路径中获取文件夹 ID
	folderID := c.Params("folderId")
	if folderID == "" {
		return fail(c, 1001, "Folder ID is required")
	}

	fmt.Printf("=== 开始删除文件夹 ===\n")
	fmt.Printf("请求删除的文件夹ID: %s\n", folderID)
	fmt.Printf("当前内存中的文件夹数量: %d\n", len(folders))
	for i, folder := range folders {
		fmt.Printf("  [%d] ID: %s, Label: %s, Path: %s\n", i, folder.ID, folder.Label, folder.Path)
	}

	// 检查文件夹是否存在
	var targetFolder *FolderEntry
	for _, folder := range folders {
		if folder.ID == folderID {
			targetFolder = &folder
			break
		}
	}

	if targetFolder == nil {
		fmt.Printf("❌ 文件夹不存在: %s\n", folderID)
		return fail(c, 1002, "Folder not found")
	}

	fmt.Printf("✅ 找到要删除的文件夹: ID=%s, Label=%s, Path=%s\n", targetFolder.ID, targetFolder.Label, targetFolder.Path)

	// 调用 syncthing API 删除文件夹
	if err := deleteSyncthingFolder(folderID); err != nil {
		fmt.Printf("❌ 调用 Syncthing API 删除失败: %v\n", err)
		return fail(c, 1003, "Failed to delete folder from syncthing: "+err.Error())
	}

	fmt.Printf("✅ Syncthing API 删除成功\n")

	// 重新从 Syncthing 加载文件夹列表
	if err := reloadFoldersFromSyncthing(); err != nil {
		fmt.Printf("❌ 重新加载文件夹列表失败: %v\n", err)
		// 即使重新加载失败，也从内存中删除该文件夹
		mu.Lock()
		var newFolders []FolderEntry
		for _, folder := range folders {
			if folder.ID != folderID {
				newFolders = append(newFolders, folder)
			}
		}
		folders = newFolders
		mu.Unlock()
		fmt.Printf("✅ 从内存中删除文件夹\n")
	} else {
		fmt.Printf("✅ 重新加载文件夹列表成功\n")
	}

	fmt.Printf("=== 删除文件夹完成 ===\n")

	return success(c, map[string]interface{}{
		"message": "Folder deleted successfully",
		"folder":  targetFolder,
	})
}

// 调用 syncthing API 删除文件夹
func deleteSyncthingFolder(folderID string) error {
	// 构建 syncthing API URL
	syncthingURL := fmt.Sprintf("http://127.0.0.1:8384/rest/config/folders/%s", folderID)

	// 创建请求
	req, err := http.NewRequest("DELETE", syncthingURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %v", err)
	}

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request to syncthing: %v", err)
	}
	defer resp.Body.Close()

	// 检查响应状态
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("syncthing API returned status %d: %s", resp.StatusCode, string(body))
	}

	fmt.Printf("成功调用 syncthing API 删除文件夹: %s\n", folderID)
	return nil
}

// 从 Syncthing 重新加载文件夹列表
func reloadFoldersFromSyncthing() error {
	fmt.Printf("=== 开始重新加载文件夹列表 ===\n")

	// 构建 syncthing API URL
	syncthingURL := "http://127.0.0.1:8384/rest/config/folders"
	fmt.Printf("Syncthing API URL: %s\n", syncthingURL)

	// 创建请求
	req, err := http.NewRequest("GET", syncthingURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %v", err)
	}

	// 添加 API Key 认证（如果需要）
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
		fmt.Printf("使用 API Key 认证\n")
	} else {
		fmt.Printf("未使用 API Key 认证\n")
	}

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request to syncthing: %v", err)
	}
	defer resp.Body.Close()

	fmt.Printf("Syncthing API 响应状态: %d\n", resp.StatusCode)

	// 检查响应状态
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("syncthing API returned status %d: %s", resp.StatusCode, string(body))
	}

	// 读取响应体
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %v", err)
	}

	fmt.Printf("响应体长度: %d 字节\n", len(body))
	fmt.Printf("响应体内容: %s\n", string(body))

	// 解析响应
	var syncthingFolders []FolderEntry
	if err := json.Unmarshal(body, &syncthingFolders); err != nil {
		return fmt.Errorf("failed to unmarshal response: %v", err)
	}

	fmt.Printf("解析到 %d 个文件夹:\n", len(syncthingFolders))
	for i, folder := range syncthingFolders {
		fmt.Printf("  [%d] ID: %s, Label: %s, Path: %s\n", i, folder.ID, folder.Label, folder.Path)
	}

	// 更新内存中的文件夹列表
	mu.Lock()
	oldCount := len(folders)
	folders = syncthingFolders
	mu.Unlock()

	fmt.Printf("✅ 成功从 Syncthing 重新加载文件夹列表，旧数量: %d, 新数量: %d\n", oldCount, len(syncthingFolders))
	fmt.Printf("=== 重新加载文件夹列表完成 ===\n")
	return nil
}

// 获取本机设备ID
func getLocalDeviceID() (string, error) {
	req, err := http.NewRequest("GET", "https://127.0.0.1:8384/rest/system/status", nil)
	if err != nil {
		return "", fmt.Errorf("failed to create request: %v", err)
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	// 创建跳过证书验证的 HTTP 客户端
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to request syncthing: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("syncthing status api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %v", err)
	}

	var status map[string]interface{}
	if err := json.Unmarshal(body, &status); err != nil {
		return "", fmt.Errorf("failed to parse response: %v", err)
	}

	if myID, ok := status["myID"].(string); ok {
		return myID, nil
	}

	return "", fmt.Errorf("myID not found in status response")
}

// 获取本机设备ID
func getLocalDeviceIDHandler(c *fiber.Ctx) error {
	fmt.Printf("=== 获取本机设备ID ===\n")

	req, err := http.NewRequest("GET", "https://127.0.0.1:8384/rest/system/status", nil)
	if err != nil {
		fmt.Printf("创建状态请求失败: %v\n", err)
		return fail(c, 1001, "Failed to create request: "+err.Error())
	}
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	// 创建跳过证书验证的 HTTP 客户端
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("状态 HTTP 请求失败: %v\n", err)
		return fail(c, 1002, "Failed to request syncthing: "+err.Error())
	}
	defer resp.Body.Close()

	fmt.Printf("状态 HTTP 响应状态码: %d\n", resp.StatusCode)
	if resp.StatusCode != 200 {
		fmt.Printf("Syncthing 状态 API 错误: %s\n", resp.Status)
		return fail(c, 1003, "syncthing status api error: "+resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("读取状态响应体失败: %v\n", err)
		return fail(c, 1004, "Failed to read response: "+err.Error())
	}

	var status map[string]interface{}
	if err := json.Unmarshal(body, &status); err != nil {
		fmt.Printf("状态 JSON 解析失败: %v\n", err)
		return fail(c, 1005, "Failed to parse response: "+err.Error())
	}

	if myID, ok := status["myID"].(string); ok {
		fmt.Printf("成功获取本机设备ID: %s\n", myID)
		return success(c, map[string]interface{}{
			"deviceID": myID,
		})
	}

	fmt.Printf("状态响应中未找到myID字段\n")
	fmt.Printf("状态响应内容: %s\n", string(body))
	return fail(c, 1006, "myID not found in status response")
}
