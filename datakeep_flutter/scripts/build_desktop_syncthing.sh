#!/bin/bash
# 桌面端 Syncthing 二进制（Linux / macOS / Windows）
# 输出：
#   本机：datakeep_flutter/bin/syncthing（Windows 为 syncthing.exe）
#   交叉：SYNCTHING_GOOS=windows SYNCTHING_GOARCH=amd64 → bin/syncthing.exe
#
# 用法:
#   bash scripts/build_desktop_syncthing.sh
#   SYNCTHING_GOOS=windows SYNCTHING_GOARCH=amd64 bash scripts/build_desktop_syncthing.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SYNCTHING_DIR="$(cd "$FLUTTER_DIR/.." && pwd)/syncthing"
VERSION="${SYNCTHING_BUILD_VERSION:-v2.1.3}"

GOOS_TARGET="${SYNCTHING_GOOS:-}"
GOARCH_TARGET="${SYNCTHING_GOARCH:-}"

if [[ -z "$GOOS_TARGET" ]]; then
  case "$(uname -s)" in
    Darwin) GOOS_TARGET=darwin ;;
    Linux) GOOS_TARGET=linux ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) GOOS_TARGET=windows ;;
    *) GOOS_TARGET="$(go env GOOS 2>/dev/null || echo linux)" ;;
  esac
fi

if [[ -z "$GOARCH_TARGET" ]]; then
  case "$(uname -m)" in
    x86_64|amd64) GOARCH_TARGET=amd64 ;;
    arm64|aarch64) GOARCH_TARGET=arm64 ;;
    *) GOARCH_TARGET="$(go env GOARCH 2>/dev/null || echo amd64)" ;;
  esac
fi

if [[ "$GOOS_TARGET" == "windows" ]]; then
  OUT_NAME="syncthing.exe"
else
  OUT_NAME="syncthing"
fi
OUT="$FLUTTER_DIR/bin/$OUT_NAME"

command -v go >/dev/null || {
  echo -e "${RED}未找到 go，请先安装 Go${NC}" >&2
  exit 1
}

# snap go 权限受限时优先用完整路径
if [[ -x /snap/go/current/bin/go ]]; then
  export PATH="/snap/go/current/bin:${PATH}"
fi

if [[ ! -d "$SYNCTHING_DIR" ]] || [[ ! -f "$SYNCTHING_DIR/build.go" ]]; then
  echo -e "${RED}Syncthing 源码不存在: $SYNCTHING_DIR${NC}" >&2
  exit 1
fi

mkdir -p "$FLUTTER_DIR/bin"

if [[ -f "$OUT" ]] && [[ "$OUT" -nt "$SYNCTHING_DIR/build.go" ]]; then
  echo -e "${GREEN}✓ Syncthing 已是最新: $OUT${NC}"
  exit 0
fi

echo -e "${YELLOW}编译 Syncthing → $OUT (version=$VERSION goos=$GOOS_TARGET goarch=$GOARCH_TARGET)${NC}"
cd "$SYNCTHING_DIR"
# 清理同目录残留，避免 mv 冲突
rm -f syncthing syncthing.exe

# Windows：GUI 子系统，避免 DataKeep 启动/退出时闪控制台窗口
if [[ "$GOOS_TARGET" == "windows" ]]; then
  export EXTRA_LDFLAGS="${EXTRA_LDFLAGS:+$EXTRA_LDFLAGS }-H windowsgui"
fi

go run build.go -version "$VERSION" -no-upgrade -goos "$GOOS_TARGET" -goarch "$GOARCH_TARGET" build syncthing

if [[ -f "syncthing.exe" ]]; then
  mv -f syncthing.exe "$OUT"
elif [[ -f "syncthing" ]]; then
  mv -f syncthing "$OUT"
else
  echo -e "${RED}编译后未找到 syncthing 可执行文件${NC}" >&2
  exit 1
fi

chmod +x "$OUT" 2>/dev/null || true
echo -e "${GREEN}✅ Syncthing 编译完成: $OUT${NC}"
