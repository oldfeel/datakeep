#!/bin/bash
# 桌面端（Linux / macOS / Windows 交叉编译前本机构建）Syncthing 二进制
# 输出：datakeep_flutter/bin/syncthing

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SYNCTHING_DIR="$(cd "$FLUTTER_DIR/.." && pwd)/syncthing"
OUT="$FLUTTER_DIR/bin/syncthing"
VERSION="${SYNCTHING_BUILD_VERSION:-v2.1.0}"

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

echo -e "${YELLOW}编译 Syncthing → $OUT (version=$VERSION)${NC}"
cd "$SYNCTHING_DIR"
go run build.go -version "$VERSION" -no-upgrade build syncthing
mv -f syncthing "$OUT"
chmod +x "$OUT"
echo -e "${GREEN}✅ Syncthing 编译完成: $OUT${NC}"
