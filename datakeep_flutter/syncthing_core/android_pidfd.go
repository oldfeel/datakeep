//go:build android

package mdst

import (
	"fmt"
	_ "unsafe"
)

// Android < 12 的 seccomp 拦截 pidfd_*，Go 1.23+ 探测时会 SIGSYS 闪退。
// gomobile 共享库里 Go 内部忽略 SIGSYS 不可靠，启动前直接禁用 pidfd。
// 需 gomobile bind -ldflags="-checklinkname=0"。
// 参考：https://github.com/golang/go/issues/70508

//go:linkname checkPidfdOnce os.checkPidfdOnce
var checkPidfdOnce func() error

func init() {
	checkPidfdOnce = func() error {
		return fmt.Errorf("pidfd disabled on Android (seccomp)")
	}
}
