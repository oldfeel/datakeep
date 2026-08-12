#!/bin/bash
# DataKeep Flutter iOS：编译进程内 Syncthing 引擎并启动模拟器/真机

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}DataKeep iOS 启动${NC}"

if ! command -v flutter &>/dev/null; then
  echo -e "${RED}未找到 flutter${NC}"
  exit 1
fi
if ! command -v go &>/dev/null; then
  echo -e "${RED}未找到 go${NC}"
  exit 1
fi

export PATH="${HOME}/go/bin:/opt/homebrew/bin:${PATH}"

# 可选：沿用本机已 export 的代理；未设置时可手动 export
if [[ -n "${https_proxy:-}${http_proxy:-}" ]]; then
  echo -e "${YELLOW}使用代理: https_proxy=${https_proxy:-} http_proxy=${http_proxy:-}${NC}"
fi
export GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"

echo -e "${GREEN}1/2 构建 syncthing_core xcframework${NC}"
make -C syncthing_core ios

echo -e "${GREEN}2/2 flutter pub get + 运行 iOS${NC}"
flutter pub get
cd ios && pod install && cd ..

DEVICE="${1:-}"
if [[ -n "$DEVICE" ]]; then
  exec flutter run -d "$DEVICE"
fi
exec flutter run -d ios
