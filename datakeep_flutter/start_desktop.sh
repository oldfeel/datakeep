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

# Linux Debug 默认链 CEF Debug，中文输入法会 DCHECK 闪退；对齐 Windows 用 Release CEF
if [[ "$(uname -s)" == "Linux" ]]; then
  bash "$SCRIPT_DIR/scripts/ensure_webview_cef_linux_release.sh"
fi

echo -e "\n${BLUE}🖥️  检测桌面平台${NC}"
# 勿用 `flutter devices | grep -q`：grep 提前关管会导致 Broken pipe，误判无设备
case "$(uname -s)" in
  Linux*) PLATFORM="linux" ;;
  Darwin*) PLATFORM="macos" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
  *)
    echo -e "${RED}❌ 不支持的操作系统: $(uname -s)${NC}"
    exit 1
    ;;
esac

echo -e "${GREEN}✅ 使用平台: $PLATFORM${NC}"
echo -e "\n${BLUE}🚀 flutter run -d $PLATFORM${NC}"
flutter run -d "$PLATFORM"
