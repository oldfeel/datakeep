#!/bin/bash
# DataKeep macOS 桌面：编译 Syncthing + 启动 Flutter（与 Linux 桌面一致，使用 bin/syncthing）

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${GREEN}DataKeep macOS 启动${NC}"

command -v flutter >/dev/null || { echo -e "${RED}未找到 flutter${NC}"; exit 1; }

echo -e "\n${BLUE}1/3 编译桌面 Syncthing${NC}"
bash "$SCRIPT_DIR/scripts/build_desktop_syncthing.sh"

echo -e "\n${BLUE}2/3 flutter pub get${NC}"
flutter pub get

echo -e "\n${BLUE}3/3 flutter run -d macos${NC}"
flutter run -d macos
