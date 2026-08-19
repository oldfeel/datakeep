#!/bin/bash
# DataKeep Flutter 桌面客户端：编译 Syncthing + 启动 Flutter
# 后端为 Dart shelf（进程内）；Syncthing 为 bin/syncthing（与 Linux 相同）

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${GREEN}🚀 DataKeep 桌面客户端启动${NC}"
echo "=================================="

command -v flutter >/dev/null || {
  echo -e "${RED}❌ Flutter 未安装或未添加到 PATH${NC}"
  exit 1
}

command -v go >/dev/null || {
  echo -e "${RED}❌ Go 未安装（编译 Syncthing 需要）${NC}"
  exit 1
}

echo -e "\n${BLUE}📦 编译 Syncthing${NC}"
bash "$SCRIPT_DIR/scripts/build_desktop_syncthing.sh"

echo -e "\n${BLUE}📦 flutter pub get${NC}"
flutter pub get

echo -e "\n${BLUE}🖥️  检测桌面平台${NC}"
PLATFORM=""
if flutter devices | grep -q "macos"; then
  PLATFORM="macos"
elif flutter devices | grep -q "linux"; then
  PLATFORM="linux"
elif flutter devices | grep -q "windows"; then
  PLATFORM="windows"
fi

if [[ -z "$PLATFORM" ]]; then
  echo -e "${RED}❌ 未检测到可用的桌面平台${NC}"
  exit 1
fi

echo -e "${GREEN}✅ 使用平台: $PLATFORM${NC}"
echo -e "\n${BLUE}🚀 flutter run -d $PLATFORM${NC}"
flutter run -d "$PLATFORM"
