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

# Windows 防火墙/属性显示名（与 kAppDisplayName 一致）
WINDOWS_PRODUCT_NAME="${SYNCTHING_WINDOWS_PRODUCT_NAME:-数据管理}"
WINDOWS_FILE_DESC="${SYNCTHING_WINDOWS_FILE_DESC:-数据管理}"
WINDOWS_COMPANY="${SYNCTHING_WINDOWS_COMPANY:-DataKeep}"
# 变更此标记会强制重编 Windows 二进制
WINDOWS_BRAND_STAMP="product=${WINDOWS_PRODUCT_NAME};desc=${WINDOWS_FILE_DESC};gui=1;v2"

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
STAMP_FILE="$FLUTTER_DIR/bin/.syncthing-build.stamp"

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

need_rebuild=1
if [[ -f "$OUT" ]] && [[ -f "$STAMP_FILE" ]]; then
  if [[ "$(cat "$STAMP_FILE" 2>/dev/null || true)" == "${GOOS_TARGET}/${GOARCH_TARGET}/${VERSION}/${WINDOWS_BRAND_STAMP}" ]]; then
    if [[ "$OUT" -nt "$SYNCTHING_DIR/build.go" ]] && [[ "$OUT" -nt "$SCRIPT_DIR/build_desktop_syncthing.sh" ]]; then
      echo -e "${GREEN}✓ Syncthing 已是最新: $OUT${NC}"
      need_rebuild=0
    fi
  fi
fi

if [[ "$need_rebuild" -eq 0 ]]; then
  exit 0
fi

echo -e "${YELLOW}编译 Syncthing → $OUT (version=$VERSION goos=$GOOS_TARGET goarch=$GOARCH_TARGET)${NC}"
cd "$SYNCTHING_DIR"
# 清理同目录残留，避免 mv 冲突
rm -f syncthing syncthing.exe

# Windows：GUI 子系统 + VERSIONINFO 显示名「数据管理」（防火墙弹窗用）
BUILD_GO_BACKUP=""
restore_build_go() {
  if [[ -n "${BUILD_GO_BACKUP:-}" ]] && [[ -f "$BUILD_GO_BACKUP" ]]; then
    mv -f "$BUILD_GO_BACKUP" "$SYNCTHING_DIR/build.go"
    BUILD_GO_BACKUP=""
  fi
}
trap restore_build_go EXIT

if [[ "$GOOS_TARGET" == "windows" ]]; then
  export EXTRA_LDFLAGS="${EXTRA_LDFLAGS:+$EXTRA_LDFLAGS }-H windowsgui"
  # CI / 本机需有 goversioninfo，否则 exe 无 FileDescription，防火墙只显示 syncthing
  if ! command -v goversioninfo >/dev/null 2>&1; then
    echo -e "${YELLOW}安装 goversioninfo（写入 Windows 版本信息）…${NC}"
    go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@v1.4.0
    export PATH="$(go env GOPATH)/bin:${PATH}"
  fi
  BUILD_GO_BACKUP="$(mktemp)"
  cp "$SYNCTHING_DIR/build.go" "$BUILD_GO_BACKUP"
  python3 - "$SYNCTHING_DIR/build.go" "$WINDOWS_PRODUCT_NAME" "$WINDOWS_FILE_DESC" "$WINDOWS_COMPANY" <<'PY'
import sys
from pathlib import Path

def go_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

path, product, desc, company = sys.argv[1:5]
text = Path(path).read_text(encoding="utf-8")
repls = {
    '"CompanyName":      "The Syncthing Authors"': f'"CompanyName":      {go_str(company)}',
    '"FileDescription":  "Syncthing - Open Source Continuous File Synchronization"': f'"FileDescription":  {go_str(desc)}',
    '"LegalCopyright":   "The Syncthing Authors"': f'"LegalCopyright":   {go_str(company)}',
    '"ProductName":      "Syncthing"': f'"ProductName":      {go_str(product)}',
}
for old, new in repls.items():
    if old not in text:
        print(f"warn: pattern not found: {old}", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old, new, 1)
Path(path).write_text(text, encoding="utf-8")
print(f"patched versioninfo → ProductName={product}")
PY
fi

go run build.go -version "$VERSION" -no-upgrade -goos "$GOOS_TARGET" -goarch "$GOARCH_TARGET" build syncthing

restore_build_go
trap - EXIT

if [[ -f "syncthing.exe" ]]; then
  mv -f syncthing.exe "$OUT"
elif [[ -f "syncthing" ]]; then
  mv -f syncthing "$OUT"
else
  echo -e "${RED}编译后未找到 syncthing 可执行文件${NC}" >&2
  exit 1
fi

chmod +x "$OUT" 2>/dev/null || true
printf '%s' "${GOOS_TARGET}/${GOARCH_TARGET}/${VERSION}/${WINDOWS_BRAND_STAMP}" > "$STAMP_FILE"
echo -e "${GREEN}✅ Syncthing 编译完成: $OUT${NC}"
