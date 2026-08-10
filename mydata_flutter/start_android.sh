#!/bin/bash
# MyData Flutter Android：构建共用 gomobile Syncthing AAR 并启动应用
# 后端为 Dart shelf（进程内），Syncthing 为 syncthing_core AAR（进程内）

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${GREEN}MyData Android 启动${NC}"

command -v flutter >/dev/null || { echo -e "${RED}未找到 flutter${NC}"; exit 1; }
command -v go >/dev/null || { echo -e "${RED}未找到 go${NC}"; exit 1; }

export PATH="${HOME}/go/bin:/usr/local/go/bin:${PATH}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

AAR="$SCRIPT_DIR/android/app/libs/syncthingcore.aar"
echo -e "\n${BLUE}1/3 构建 syncthing_core AAR${NC}"
if [[ ! -f "$AAR" ]] || [[ "$SCRIPT_DIR/syncthing_core/client.go" -nt "$AAR" ]]; then
  make -C "$SCRIPT_DIR/syncthing_core" android
else
  echo -e "${GREEN}✓ syncthingcore.aar 已是最新${NC}"
fi

echo -e "\n${BLUE}2/3 flutter pub get${NC}"
flutter pub get

echo -e "\n${BLUE}3/3 flutter run${NC}"
if command -v adb >/dev/null; then
  adb start-server >/dev/null 2>&1 || true
  DEV_ID=$(adb devices | awk '/\tdevice$/{print $1; exit}')
  if [[ -n "${DEV_ID:-}" ]]; then
    echo -e "${GREEN}设备: $DEV_ID${NC}"
    exec flutter run -d "$DEV_ID"
  fi
fi
exec flutter run
