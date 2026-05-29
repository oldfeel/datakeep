package backend

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
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"

	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
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

// 全局变量：存储从 Android 原生代码获取的本机 IP 地址
var androidLocalIPs []string
var androidLocalIPsMutex sync.Mutex

// SetLocalNetworkIPs 设置本机局域网 IP 地址（从 Android 原生代码调用）
func SetLocalNetworkIPs(ips []string) {
	androidLocalIPsMutex.Lock()
	defer androidLocalIPsMutex.Unlock()
	androidLocalIPs = ips
}

// GetLocalNetworkIPs 获取本机局域网 IP 地址（供外部调用）
func GetLocalNetworkIPs() []string {
	androidLocalIPsMutex.Lock()
	defer androidLocalIPsMutex.Unlock()
	if len(androidLocalIPs) > 0 {
		return androidLocalIPs
	}
	return []string{}
}

// 获取本机局域网IP地址
func getLocalNetworkIPs() ([]string, error) {
	// 优先使用从 Android 原生代码获取的 IP
	androidIPs := GetLocalNetworkIPs()
	if len(androidIPs) > 0 {
		return androidIPs, nil
	}

	// 如果 Android IP 不可用，尝试使用 Go 的方法（在 Android 上可能会失败）
	var localIPs []string

	// 获取所有网络接口
	interfaces, err := net.Interfaces()
	if err != nil {
		// 在 Android 上，这可能会因为权限问题失败，返回空列表而不是错误
		return []string{}, nil
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
	syncthingURL := "https://127.0.0.1:8384/rest/config/folders"

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

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	// 发送请求
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
	syncthingURL := fmt.Sprintf("https://127.0.0.1:8384/rest/config/folders/%s", folderID)
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
	syncthingURL := fmt.Sprintf("https://127.0.0.1:8384/rest/config/folders/%s", folderID)
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
	decodedFolderId, _ := url.QueryUnescape(folderId)
	if decodedFolderId == "" {
		decodedFolderId = folderId
	}

	syncthingPath := "/rest/db/browse?folder=" + url.QueryEscape(decodedFolderId)
	if path != "" {
		syncthingPath += "&path=" + url.QueryEscape(path)
	}

	return proxySyncthingRequest(c, syncthingPath, "GET", nil, nil)
}

// proxySyncthingRequest 通用的 Syncthing API 代理请求方法
// 处理所有对 Syncthing API 的请求，包括证书验证、API Key 认证等
func proxySyncthingRequest(c *fiber.Ctx, syncthingPath string, method string, body io.Reader, headers map[string]string) error {
	// 构建 syncthing API URL
	syncthingURL := "https://127.0.0.1:8384" + syncthingPath

	// 创建请求
	req, err := http.NewRequest(method, syncthingURL, body)
	if err != nil {
		return fail(c, 1005, "Failed to create request: "+err.Error())
	}

	// 添加 API Key 认证
	apiKey := getApiKeyFromConfig()
	if apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// 添加自定义请求头
	for key, value := range headers {
		req.Header.Set(key, value)
	}

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	// 发送请求
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

// 代理 syncthing 事件接口，解决跨域问题
func syncthingEventsProxyHandler(c *fiber.Ctx) error {
	// 获取查询参数
	since := c.Query("since", "0")
	timeout := c.Query("timeout", "60")
	limit := c.Query("limit", "")
	events := c.Query("events", "")

	// 构建查询参数
	params := url.Values{}
	params.Set("since", since)
	params.Set("timeout", timeout)
	if limit != "" {
		params.Set("limit", limit)
	}
	if events != "" {
		params.Set("events", events)
	}

	// 构建带查询参数的路径
	path := "/rest/events"
	if len(params) > 0 {
		path += "?" + params.Encode()
	}

	return proxySyncthingRequest(c, path, "GET", nil, nil)
}

// 代理 syncthing 设备发现接口，解决跨域问题
func syncthingDiscoveryProxyHandler(c *fiber.Ctx) error {
	// 使用通用代理方法
	err := proxySyncthingRequest(c, "/rest/system/discovery", "GET", nil, nil)
	if err != nil {
		return err
	}

	// 记录响应内容用于调试（如果需要）
	// 注意：由于 proxySyncthingRequest 已经发送了响应，这里无法再读取响应体
	// 如果需要调试日志，可以在 proxySyncthingRequest 中添加回调参数
	return nil
}

// 代理 syncthing 设备 ID 验证接口，解决跨域问题
func syncthingDeviceIdProxyHandler(c *fiber.Ctx) error {
	// 获取查询参数
	id := c.Query("id")
	if id == "" {
		return fail(c, 1002, "Missing id parameter")
	}

	// 构建带查询参数的路径
	path := fmt.Sprintf("/rest/svc/deviceid?id=%s", url.QueryEscape(id))
	return proxySyncthingRequest(c, path, "GET", nil, nil)
}

// 代理 syncthing 设备配置接口（支持 GET 和 POST），解决跨域问题
func syncthingConfigDevicesProxyHandler(c *fiber.Ctx) error {
	// 获取请求方法和请求体
	method := c.Method()
	var body io.Reader
	headers := make(map[string]string)

	if method == "POST" {
		body = bytes.NewReader(c.Body())
		headers["Content-Type"] = "application/json"
	}

	return proxySyncthingRequest(c, "/rest/config/devices", method, body, headers)
}

// Syncthing 相关 API 调用
func getDevicesFromSyncthing() ([]Device, error) {
	logger.Info("=== getDevicesFromSyncthing 开始 ===")

	// 获取 API Key
	apiKey := getApiKeyFromConfig()
	if apiKey == "" {
		logger.Error("错误: API Key 为空")
		return nil, fmt.Errorf("API Key is empty")
	}
	// 打印 API Key 的前 10 个字符用于调试
	keyPreview := apiKey
	if len(keyPreview) > 10 {
		keyPreview = keyPreview[:10] + "..."
	}
	logger.Info("使用的 API Key", zap.String("preview", keyPreview), zap.Int("length", len(apiKey)))

	// 获取设备配置
	logger.Info("正在调用 Syncthing API", zap.String("method", "GET"), zap.String("path", "/rest/config/devices"))
	req, err := http.NewRequest("GET", "https://127.0.0.1:8384/rest/config/devices", nil)
	if err != nil {
		logger.Error("创建请求失败", zap.Error(err))
		return nil, err
	}
	req.Header.Set("X-API-Key", apiKey)
	logger.Info("请求详情", zap.String("url", req.URL.String()), zap.String("apiKeyPreview", keyPreview))

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	logger.Info("发送 HTTP 请求...")
	resp, err := client.Do(req)
	if err != nil {
		logger.Error("HTTP 请求失败", zap.Error(err))
		return nil, err
	}
	defer resp.Body.Close()

	logger.Info("HTTP 响应", zap.Int("statusCode", resp.StatusCode), zap.String("status", resp.Status))
	logger.Info("响应头信息", zap.Any("headers", resp.Header))

	if resp.StatusCode != 200 {
		// 读取响应体以获取详细错误信息
		body, readErr := ioutil.ReadAll(resp.Body)
		if readErr != nil {
			logger.Error("读取错误响应体失败", zap.Error(readErr))
		} else {
			logger.Error("错误响应体内容", zap.String("body", string(body)))
		}
		logger.Error("Syncthing API 错误", zap.String("status", resp.Status))
		return nil, fmt.Errorf("syncthing api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		logger.Error("读取响应体失败", zap.Error(err))
		return nil, err
	}
	logger.Info("响应体", zap.Int("length", len(body)))
	if len(body) > 0 && len(body) < 1000 {
		// 如果响应体不太长，打印完整内容用于调试
		logger.Info("响应体内容", zap.String("body", string(body)))
	} else if len(body) > 0 {
		// 如果响应体很长，只打印前 500 个字符
		bodyPreview := string(body)
		if len(bodyPreview) > 500 {
			bodyPreview = bodyPreview[:500] + "..."
		}
		logger.Info("响应体内容预览", zap.String("preview", bodyPreview))
	}

	var devices []Device
	if err := json.Unmarshal(body, &devices); err != nil {
		logger.Error("JSON 解析失败", zap.Error(err), zap.String("body", string(body)))
		return nil, err
	}
	logger.Info("成功解析设备列表", zap.Int("count", len(devices)))
	for i, device := range devices {
		logger.Info("设备信息", zap.Int("index", i+1), zap.String("deviceID", device.DeviceID), zap.String("name", device.Name), zap.Any("addresses", device.Addresses))
	}

	// 获取设备连接状态
	fmt.Printf("\n正在获取设备连接状态...\n")
	connections, err := getDeviceConnections()
	if err != nil {
		fmt.Printf("获取设备连接状态失败: %v\n", err)
		fmt.Printf("继续返回设备列表（不包含连接信息）\n")
		logger.Info("=== getDevicesFromSyncthing 结束 ===")
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

	// 获取本机设备ID
	localDeviceID, err := getLocalDeviceID()
	if err != nil {
		fmt.Printf("获取本机设备ID失败: %v\n", err)
		localDeviceID = ""
	} else {
		fmt.Printf("本机设备ID: %s\n", localDeviceID)
	}

	// 将连接信息和发现信息合并到设备信息中
	fmt.Printf("\n正在合并连接信息到设备列表...\n")
	for i, device := range devices {
		var addresses []string

		// 检查是否为本机设备
		isLocalDevice := localDeviceID != "" && device.DeviceID == localDeviceID

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
		} else if isLocalDevice {
			// 本机设备特殊处理：设置为在线状态
			devices[i].Connected = true
			devices[i].ConnectionType = "local"
			devices[i].ClientVersion = "local"
			devices[i].InBytesTotal = 0
			devices[i].OutBytesTotal = 0
			devices[i].IsLocalNetwork = true
			devices[i].Crypto = "local"
			fmt.Printf("  本机设备 %s 设置为在线状态\n", device.Name)
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

		// 为本机设备添加本地地址
		if isLocalDevice {
			localIPs, err := getLocalNetworkIPs()
			if err == nil && len(localIPs) > 0 {
				addresses = append(addresses, localIPs...)
				fmt.Printf("  为本机设备添加本地地址: %v\n", localIPs)
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

	logger.Info("=== getDevicesFromSyncthing 结束 ===")
	return devices, nil
}

func getDeviceConnections() (map[string]ConnectionInfo, error) {
	fmt.Printf("正在调用 Syncthing API: GET /rest/system/connections\n")

	// 获取 API Key
	apiKey := getApiKeyFromConfig()
	if apiKey == "" {
		fmt.Printf("错误: API Key 为空\n")
		return nil, fmt.Errorf("API Key is empty")
	}
	keyPreview := apiKey
	if len(keyPreview) > 10 {
		keyPreview = keyPreview[:10] + "..."
	}
	fmt.Printf("使用的 API Key (预览): %s (长度: %d)\n", keyPreview, len(apiKey))

	req, err := http.NewRequest("GET", "https://127.0.0.1:8384/rest/system/connections", nil)
	if err != nil {
		fmt.Printf("创建连接状态请求失败: %v\n", err)
		return nil, err
	}
	req.Header.Set("X-API-Key", apiKey)

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
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
		// 读取响应体以获取详细错误信息
		body, readErr := ioutil.ReadAll(resp.Body)
		if readErr != nil {
			fmt.Printf("读取错误响应体失败: %v\n", readErr)
		} else {
			fmt.Printf("错误响应体内容: %s\n", string(body))
		}
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
	// 获取 API Key
	apiKey := getApiKeyFromConfig()
	if apiKey == "" {
		fmt.Printf("错误: API Key 为空\n")
		return nil, fmt.Errorf("API Key is empty")
	}

	req, err := http.NewRequest("GET", "https://127.0.0.1:8384/rest/system/status", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-API-Key", apiKey)

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		// 读取响应体以获取详细错误信息
		body, readErr := ioutil.ReadAll(resp.Body)
		if readErr == nil {
			fmt.Printf("getSystemStatus 错误响应体: %s\n", string(body))
		}
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
	// 获取 API Key
	apiKey := getApiKeyFromConfig()
	if apiKey == "" {
		fmt.Printf("错误: API Key 为空\n")
		return nil, fmt.Errorf("API Key is empty")
	}

	req, err := http.NewRequest("GET", "https://127.0.0.1:8384/rest/system/discovery", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-API-Key", apiKey)

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		// 读取响应体以获取详细错误信息
		body, readErr := ioutil.ReadAll(resp.Body)
		if readErr == nil {
			fmt.Printf("getDeviceDiscovery 错误响应体: %s\n", string(body))
		}
		return nil, fmt.Errorf("device discovery api error: %s", resp.Status)
	}

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// 记录响应内容用于调试
	if len(body) > 0 && len(body) < 2000 {
		fmt.Printf("getDeviceDiscovery 响应体: %s\n", string(body))
	} else if len(body) > 0 {
		bodyPreview := string(body)
		if len(bodyPreview) > 500 {
			bodyPreview = bodyPreview[:500] + "..."
		}
		fmt.Printf("getDeviceDiscovery 响应体预览: %s (总长度: %d)\n", bodyPreview, len(body))
	} else {
		fmt.Printf("getDeviceDiscovery 返回空响应\n")
	}

	var discovery map[string]interface{}
	if err := json.Unmarshal(body, &discovery); err != nil {
		fmt.Printf("getDeviceDiscovery JSON 解析失败: %v, 响应体: %s\n", err, string(body))
		return nil, err
	}

	fmt.Printf("getDeviceDiscovery 解析成功，设备数量: %d\n", len(discovery))
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
	syncthingURL := fmt.Sprintf("https://127.0.0.1:8384/rest/config/folders/%s", folderID)

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

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr}

	// 发送请求
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
	syncthingURL := "https://127.0.0.1:8384/rest/config/folders"
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

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
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

	// 使用 HTTPS 客户端，跳过证书验证（Syncthing 使用自签名证书）
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

// 移除设备处理器
func removeDeviceHandler(c *fiber.Ctx) error {
	// 从 URL 路径中获取设备 ID
	deviceID := c.Params("deviceId")
	if deviceID == "" {
		return fail(c, 1001, "Device ID is required")
	}

	fmt.Printf("=== 开始移除设备 ===\n")
	fmt.Printf("请求移除的设备ID: %s\n", deviceID)

	// 调用 syncthing API 移除设备
	if err := removeSyncthingDevice(deviceID); err != nil {
		fmt.Printf("❌ 调用 Syncthing API 移除设备失败: %v\n", err)
		return fail(c, 1003, "Failed to remove device from syncthing: "+err.Error())
	}

	fmt.Printf("✅ Syncthing API 移除设备成功\n")

	return success(c, map[string]interface{}{
		"message":  "设备移除成功",
		"deviceID": deviceID,
	})
}

// 调用 Syncthing API 移除设备
func removeSyncthingDevice(deviceID string) error {
	// 构建 syncthing API URL
	syncthingURL := fmt.Sprintf("https://127.0.0.1:8384/rest/config/devices/%s", deviceID)

	// 创建 DELETE 请求
	req, err := http.NewRequest("DELETE", syncthingURL, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %v", err)
	}

	// 添加 API Key 认证
	req.Header.Set("X-API-Key", getApiKeyFromConfig())

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request: %v", err)
	}
	defer resp.Body.Close()

	// 检查响应状态
	if resp.StatusCode != 200 {
		body, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("syncthing api error: %s, response: %s", resp.Status, string(body))
	}

	fmt.Printf("✅ Syncthing API 移除设备成功: %s\n", deviceID)
	return nil
}

// 获取当前WiFi信息
func getWifiInfoHandler(c *fiber.Ctx) error {
	fmt.Printf("=== 获取WiFi信息 ===\n")

	var wifiName string
	var err error

	// 根据操作系统获取WiFi信息
	switch runtime.GOOS {
	case "linux":
		wifiName, err = getWifiInfoLinux()
	case "darwin":
		wifiName, err = getWifiInfoDarwin()
	case "windows":
		wifiName, err = getWifiInfoWindows()
	default:
		wifiName = "未知系统"
	}

	if err != nil {
		fmt.Printf("获取WiFi信息失败: %v\n", err)
		return success(c, map[string]interface{}{
			"wifiName": "获取失败",
			"error":    err.Error(),
		})
	}

	fmt.Printf("成功获取WiFi名称: %s\n", wifiName)
	return success(c, map[string]interface{}{
		"wifiName": wifiName,
	})
}

// Linux系统获取WiFi信息
func getWifiInfoLinux() (string, error) {
	// 尝试使用iwgetid命令获取当前WiFiSSID
	cmd := exec.Command("iwgetid", "-r")
	output, err := cmd.Output()
	if err == nil {
		wifiName := strings.TrimSpace(string(output))
		if wifiName != "" {
			return wifiName, nil
		}
	}

	// 如果iwgetid失败，尝试使用nmcli命令
	cmd = exec.Command("nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi")
	output, err = cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.HasPrefix(line, "yes:") {
				parts := strings.Split(line, ":")
				if len(parts) >= 2 {
					wifiName := strings.TrimSpace(parts[1])
					if wifiName != "" {
						return wifiName, nil
					}
				}
			}
		}
	}

	return "未连接", nil
}

// macOS系统获取WiFi信息
func getWifiInfoDarwin() (string, error) {
	cmd := exec.Command("/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", "-I")
	output, err := cmd.Output()
	if err != nil {
		return "未连接", err
	}

	// 解析输出查找SSID
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, " SSID:") {
			parts := strings.Split(line, ":")
			if len(parts) >= 2 {
				wifiName := strings.TrimSpace(parts[1])
				if wifiName != "" {
					return wifiName, nil
				}
			}
		}
	}

	return "未连接", nil
}

// Windows系统获取WiFi信息
func getWifiInfoWindows() (string, error) {
	cmd := exec.Command("netsh", "wlan", "show", "interfaces")
	output, err := cmd.Output()
	if err != nil {
		return "未连接", err
	}

	// 解析输出查找SSID
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if strings.Contains(line, "SSID") && strings.Contains(line, ":") {
			parts := strings.Split(line, ":")
			if len(parts) >= 2 {
				wifiName := strings.TrimSpace(parts[1])
				if wifiName != "" && wifiName != "BSSID" {
					return wifiName, nil
				}
			}
		}
	}

	return "未连接", nil
}

// 文件预览处理器
func filePreviewHandler(c *fiber.Ctx) error {
	folderID := c.Params("folderId")
	if folderID == "" {
		return fail(c, 400, "文件夹ID不能为空")
	}

	// 新增：对 folderID 做 URL 解码，兼容中文和特殊字符的文件夹ID
	if decodedID, err := url.QueryUnescape(folderID); err == nil {
		folderID = decodedID
	}

	filePath := c.Query("path")
	if filePath == "" {
		return fail(c, 400, "文件路径不能为空")
	}

	// 添加URL解码调试信息
	fmt.Printf("原始URL路径参数: %s\n", filePath)
	// 尝试URL解码
	if decodedPath, err := url.QueryUnescape(filePath); err == nil {
		fmt.Printf("URL解码后路径: %s\n", decodedPath)
		filePath = decodedPath
	} else {
		fmt.Printf("URL解码失败: %v，使用原始路径\n", err)
	}

	// 获取文件夹信息
	folders, err := loadFoldersFromSyncthing()
	if err != nil {
		fmt.Printf("从 Syncthing API 获取文件夹信息失败: %v，尝试从配置文件读取\n", err)
		// 回退到从配置文件读取
		loadFoldersFromConfig()
		folders = folders // 使用全局变量
	}

	fmt.Printf("获取到 %d 个文件夹\n", len(folders))
	for _, folder := range folders {
		fmt.Printf("文件夹: ID=%s, 路径=%s\n", folder.ID, folder.Path)
	}

	var targetFolder *FolderEntry
	for _, folder := range folders {
		if folder.ID == folderID {
			targetFolder = &folder
			break
		}
	}

	if targetFolder == nil {
		fmt.Printf("未找到文件夹: %s\n", folderID)
		return fail(c, 404, "文件夹不存在")
	}

	fmt.Printf("找到目标文件夹: ID=%s, 路径=%s\n", targetFolder.ID, targetFolder.Path)

	// 构建完整的文件路径，展开 ~ 符号
	expandedFolderPath := expandPath(targetFolder.Path)
	fullPath := filepath.Join(expandedFolderPath, filePath)

	fmt.Printf("原始文件夹路径: %s\n", targetFolder.Path)
	fmt.Printf("展开后文件夹路径: %s\n", expandedFolderPath)
	fmt.Printf("完整文件路径: %s\n", fullPath)

	// 添加调试日志
	fmt.Printf("文件预览请求 - 文件夹ID: %s, 文件路径: %s\n", folderID, filePath)
	fmt.Printf("文件夹路径: %s\n", targetFolder.Path)
	fmt.Printf("完整文件路径: %s\n", fullPath)

	// 安全检查：确保文件路径在文件夹内
	absFolderPath, err := filepath.Abs(expandPath(targetFolder.Path))
	if err != nil {
		fmt.Printf("获取文件夹绝对路径失败: %v\n", err)
		return fail(c, 500, "获取文件夹绝对路径失败: "+err.Error())
	}

	absFilePath, err := filepath.Abs(fullPath)
	if err != nil {
		fmt.Printf("获取文件绝对路径失败: %v\n", err)
		return fail(c, 500, "获取文件绝对路径失败: "+err.Error())
	}

	fmt.Printf("文件夹绝对路径: %s\n", absFolderPath)
	fmt.Printf("文件绝对路径: %s\n", absFilePath)

	// 检查文件路径是否在文件夹内
	if !strings.HasPrefix(absFilePath, absFolderPath) {
		fmt.Printf("路径安全检查失败: 文件路径不在文件夹内\n")
		return fail(c, 403, "访问被拒绝：文件路径不在文件夹内")
	}

	// 检查文件是否存在
	fmt.Printf("尝试访问文件: %s\n", fullPath)

	// 先检查文件夹是否存在
	if folderInfo, err := os.Stat(expandedFolderPath); err != nil {
		fmt.Printf("文件夹不存在: %s, 错误: %v\n", expandedFolderPath, err)
		return fail(c, 404, "文件夹不存在")
	} else {
		fmt.Printf("文件夹存在: %s, 权限: %v\n", expandedFolderPath, folderInfo.Mode())
	}

	fileInfo, err := os.Stat(fullPath)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Printf("文件不存在: %s\n", fullPath)
			// 列出文件夹内容以帮助调试
			if files, err := os.ReadDir(expandedFolderPath); err == nil {
				fmt.Printf("文件夹内容:\n")
				for _, file := range files {
					fmt.Printf("  - %s (目录: %v)\n", file.Name(), file.IsDir())
				}
			}
			return fail(c, 404, "文件不存在")
		}
		fmt.Printf("检查文件失败: %v\n", err)
		return fail(c, 500, "检查文件失败: "+err.Error())
	}

	// 检查是否为目录
	if fileInfo.IsDir() {
		return fail(c, 400, "不能预览目录")
	}

	// 获取文件扩展名
	ext := strings.ToLower(filepath.Ext(fullPath))

	// 根据文件类型设置不同的 Content-Type
	var contentType string
	switch ext {
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".png":
		contentType = "image/png"
	case ".gif":
		contentType = "image/gif"
	case ".bmp":
		contentType = "image/bmp"
	case ".svg":
		contentType = "image/svg+xml"
	case ".webp":
		contentType = "image/webp"
	case ".pdf":
		contentType = "application/pdf"
	case ".mp4":
		contentType = "video/mp4"
	case ".avi":
		contentType = "video/x-msvideo"
	case ".mov":
		contentType = "video/quicktime"
	case ".webm":
		contentType = "video/webm"
	case ".mp3":
		contentType = "audio/mpeg"
	case ".wav":
		contentType = "audio/wav"
	case ".ogg":
		contentType = "audio/ogg"
	case ".txt", ".md":
		contentType = "text/plain; charset=utf-8"
	case ".json":
		contentType = "application/json"
	case ".xml":
		contentType = "application/xml"
	case ".html", ".htm":
		contentType = "text/html; charset=utf-8"
	case ".css":
		contentType = "text/css"
	case ".js":
		contentType = "application/javascript"
	case ".py":
		contentType = "text/plain; charset=utf-8"
	case ".java":
		contentType = "text/plain; charset=utf-8"
	case ".cpp", ".c":
		contentType = "text/plain; charset=utf-8"
	case ".go":
		contentType = "text/plain; charset=utf-8"
	case ".rs":
		contentType = "text/plain; charset=utf-8"
	case ".php":
		contentType = "text/plain; charset=utf-8"
	case ".rb":
		contentType = "text/plain; charset=utf-8"
	case ".swift":
		contentType = "text/plain; charset=utf-8"
	case ".kt":
		contentType = "text/plain; charset=utf-8"
	case ".dart":
		contentType = "text/plain; charset=utf-8"
	default:
		// 对于未知类型，尝试读取文件头来判断
		file, err := os.Open(fullPath)
		if err != nil {
			return fail(c, 500, "打开文件失败: "+err.Error())
		}
		defer file.Close()

		// 读取文件头
		buffer := make([]byte, 512)
		n, err := file.Read(buffer)
		if err != nil && err != io.EOF {
			return fail(c, 500, "读取文件失败: "+err.Error())
		}

		// 使用 http.DetectContentType 检测类型
		contentType = http.DetectContentType(buffer[:n])
	}

	// 设置响应头
	c.Set("Content-Type", contentType)
	c.Set("Content-Disposition", fmt.Sprintf("inline; filename=\"%s\"", filepath.Base(fullPath)))

	// 对于文本文件，读取内容并返回
	if strings.HasPrefix(contentType, "text/") ||
		contentType == "application/json" ||
		contentType == "application/xml" ||
		contentType == "application/javascript" {

		content, err := ioutil.ReadFile(fullPath)
		if err != nil {
			return fail(c, 500, "读取文件内容失败: "+err.Error())
		}

		return c.Send(content)
	}

	// 对于二进制文件（图片、视频、音频等），直接发送文件
	return c.SendFile(fullPath)
}
