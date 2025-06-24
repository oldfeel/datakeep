package main

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
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
	return success(c, folders)
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

		// 应用局域网地址过滤
		filteredAddresses := filterAndExtractIPAddresses(uniqueAddresses)
		// 确保 addresses 始终是一个数组而不是 nil
		if filteredAddresses == nil {
			filteredAddresses = []string{}
		}
		devices[i].Addresses = filteredAddresses
		fmt.Printf("  设备 %s 更新地址: %v, 连接状态: %t, 类型: %s\n",
			device.Name, filteredAddresses, devices[i].Connected, devices[i].ConnectionType)
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
