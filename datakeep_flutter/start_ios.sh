#!/bin/bash
# DataKeep Flutter iOS：编译进程内 Syncthing 引擎并启动真机/模拟器
# 用法：
#   ./start_ios.sh                  # 优先真机，其次模拟器
#   ./start_ios.sh <device_id>      # 指定设备（见 flutter devices）
#   SKIP_IOS_ENGINE=1 ./start_ios.sh  # 跳过 syncthing_core 重建

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}DataKeep iOS 启动${NC}"

if [[ -n "${SSH_CONNECTION:-}" ]]; then
  echo -e "${YELLOW}检测到 SSH 会话：代码签名/本地网络调试易失败。建议在 Mac 本机终端运行；若坚持 SSH 请先：${NC}"
  echo -e "${YELLOW}  security unlock-keychain ~/Library/Keychains/login.keychain-db${NC}"
  echo -e "${YELLOW}并在「系统设置 → 隐私与安全性 → 本地网络」允许终端/Cursor。${NC}"
fi

command -v flutter >/dev/null || { echo -e "${RED}未找到 flutter${NC}"; exit 1; }
command -v go >/dev/null || { echo -e "${RED}未找到 go${NC}"; exit 1; }
command -v python3 >/dev/null || { echo -e "${RED}未找到 python3（用于解析 flutter devices）${NC}"; exit 1; }

export PATH="${HOME}/go/bin:/opt/homebrew/bin:${PATH}"

# 国内拉 golang.org/x/mobile 常超时：优先 goproxy.cn；仍失败再开本地 HTTP 代理
if [[ -n "${https_proxy:-}${http_proxy:-}" ]]; then
  echo -e "${YELLOW}使用代理: https_proxy=${https_proxy:-} http_proxy=${http_proxy:-}${NC}"
fi
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
echo -e "${YELLOW}GOPROXY=${GOPROXY}${NC}"

XCFRAMEWORK="$SCRIPT_DIR/syncthing_core/build/DataKeepSyncthing.xcframework"
# 引擎链入 syncthing 子模块；任一更新都需重建（connections / relay 易漏检）
ST_CONN="$SCRIPT_DIR/../syncthing/lib/connections/service.go"
ST_RELAY="$SCRIPT_DIR/../syncthing/lib/relay/client/dynamic.go"
echo -e "\n${BLUE}1/3 构建 syncthing_core xcframework${NC}"
if [[ "${SKIP_IOS_ENGINE:-}" == "1" ]]; then
  echo -e "${YELLOW}跳过引擎构建（SKIP_IOS_ENGINE=1）${NC}"
elif [[ ! -d "$XCFRAMEWORK" ]] \
  || [[ "$SCRIPT_DIR/syncthing_core/client.go" -nt "$XCFRAMEWORK" ]] \
  || [[ -f "$ST_CONN" && "$ST_CONN" -nt "$XCFRAMEWORK" ]] \
  || [[ -f "$ST_RELAY" && "$ST_RELAY" -nt "$XCFRAMEWORK" ]]; then
  make -C "$SCRIPT_DIR/syncthing_core" ios
else
  echo -e "${GREEN}✓ DataKeepSyncthing.xcframework 已是最新${NC}"
fi

echo -e "\n${BLUE}2/3 flutter pub get + pod install${NC}"
flutter pub get
(
  cd ios
  if ! pod install; then
    echo -e "${YELLOW}pod install 失败，尝试清理后重装（CDN/锁文件冲突时常见）${NC}"
    rm -f Podfile.lock
    pod install
  fi
)

# 从 flutter devices --machine 选设备：优先真机，其次模拟器；输出 id<TAB>name
pick_ios_device() {
  flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
devices = json.load(sys.stdin)
ios = [d for d in devices if d.get("targetPlatform") == "ios"]
physical = [d for d in ios if not d.get("emulator")]
sims = [d for d in ios if d.get("emulator")]
chosen = (physical or sims or [None])[0]
if not chosen:
    sys.exit(1)
print(chosen["id"] + "\t" + chosen.get("name", chosen["id"]))
'
}

echo -e "\n${BLUE}3/3 flutter run${NC}"
DEVICE="${1:-}"
if [[ -n "$DEVICE" ]]; then
  echo -e "${GREEN}设备: $DEVICE${NC}"
  exec flutter run -d "$DEVICE"
fi

if DEVICE_LINE="$(pick_ios_device)"; then
  DEVICE_ID="${DEVICE_LINE%%$'\t'*}"
  DEVICE_NAME="${DEVICE_LINE#*$'\t'}"
  echo -e "${GREEN}自动选择: ${DEVICE_NAME} (${DEVICE_ID})${NC}"
  exec flutter run -d "$DEVICE_ID"
fi

echo -e "${RED}未检测到 iOS 设备或模拟器${NC}"
echo -e "${YELLOW}请用数据线连接并解锁真机，或先启动模拟器，然后执行：${NC}"
echo "  flutter devices"
echo "  ./start_ios.sh <device_id>"
exit 1
