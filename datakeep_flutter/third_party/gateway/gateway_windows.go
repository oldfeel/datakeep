//go:build windows
// +build windows

package gateway

import (
	"encoding/binary"
	"net"
	"syscall"
	"unsafe"
)

// 用 IP Helper API 读路由表，避免 exec route.exe 闪控制台。

var (
	modiphlpapi           = syscall.NewLazyDLL("iphlpapi.dll")
	procGetIpForwardTable = modiphlpapi.NewProc("GetIpForwardTable")
)

type mibIPForwardRow struct {
	ForwardDest      uint32
	ForwardMask      uint32
	ForwardPolicy    uint32
	ForwardNextHop   uint32
	ForwardIfIndex   uint32
	ForwardType      uint32
	ForwardProto     uint32
	ForwardAge       uint32
	ForwardNextHopAS uint32
	ForwardMetric1   uint32
	ForwardMetric2   uint32
	ForwardMetric3   uint32
	ForwardMetric4   uint32
	ForwardMetric5   uint32
}

const errorInsufficientBuffer = 122

func discoverGatewaysOSSpecific() (ips []net.IP, err error) {
	rows, err := getIPForwardTable()
	if err != nil {
		return nil, err
	}

	type cand struct {
		ip     net.IP
		metric uint32
	}
	var cands []cand
	seen := map[string]struct{}{}
	for _, r := range rows {
		if r.ForwardDest != 0 {
			continue
		}
		ip := dwordToIPv4(r.ForwardNextHop)
		if ip == nil || ip.IsUnspecified() {
			continue
		}
		s := ip.String()
		if _, ok := seen[s]; ok {
			continue
		}
		seen[s] = struct{}{}
		cands = append(cands, cand{ip: ip, metric: r.ForwardMetric1})
	}
	if len(cands) == 0 {
		return nil, &ErrNoGateway{}
	}

	// 最低 metric 优先
	best := 0
	for i := 1; i < len(cands); i++ {
		if cands[i].metric < cands[best].metric {
			best = i
		}
	}
	ips = append(ips, cands[best].ip)
	for i, c := range cands {
		if i == best {
			continue
		}
		ips = append(ips, c.ip)
	}
	return ips, nil
}

func discoverGatewayInterfaceOSSpecific() (ip net.IP, err error) {
	// Syncthing 仅用 DiscoverGateway；接口 IP 回退为网关探测结果
	ips, err := discoverGatewaysOSSpecific()
	if err != nil {
		return nil, err
	}
	return ips[0], nil
}

func getIPForwardTable() ([]mibIPForwardRow, error) {
	var size uint32
	r0, _, _ := procGetIpForwardTable.Call(0, uintptr(unsafe.Pointer(&size)), 0)
	if r0 != 0 && r0 != errorInsufficientBuffer {
		return nil, syscall.Errno(r0)
	}
	if size == 0 {
		return nil, &ErrNoGateway{}
	}
	buf := make([]byte, size)
	r0, _, _ = procGetIpForwardTable.Call(
		uintptr(unsafe.Pointer(&buf[0])),
		uintptr(unsafe.Pointer(&size)),
		1, // sorted
	)
	if r0 != 0 {
		return nil, syscall.Errno(r0)
	}
	n := *(*uint32)(unsafe.Pointer(&buf[0]))
	rowSize := unsafe.Sizeof(mibIPForwardRow{})
	offset := unsafe.Sizeof(uint32(0))
	rows := make([]mibIPForwardRow, 0, n)
	for i := uint32(0); i < n; i++ {
		off := offset + uintptr(i)*rowSize
		if off+rowSize > uintptr(len(buf)) {
			break
		}
		row := *(*mibIPForwardRow)(unsafe.Pointer(&buf[off]))
		rows = append(rows, row)
	}
	return rows, nil
}

// MIB IP 字段为网络字节序；在 LE 机器上按 uint32 读入后用 LittleEndian 还原字节。
func dwordToIPv4(n uint32) net.IP {
	ip := make(net.IP, 4)
	binary.LittleEndian.PutUint32(ip, n)
	return ip
}