#!/bin/bash
# Linux 内置音视频（media_kit）构建依赖准备
# 用法:
#   export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897
#   ./scripts/linux_media_deps.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MIMALLOC_URL="https://github.com/microsoft/mimalloc/archive/refs/tags/v2.1.2.tar.gz"
MIMALLOC_MD5="5179c8f5cf1237d2300e2d8559a7bc55"
MIMALLOC_DIR="$PROJECT_DIR/build/linux/x64/debug"
MIMALLOC_FILE="$MIMALLOC_DIR/mimalloc-2.1.2.tar.gz"

echo "==> 检查系统依赖 libmpv-dev ..."
if ! pkg-config --exists mpv 2>/dev/null; then
  echo "未找到 libmpv。请安装："
  echo "  sudo apt install libmpv-dev mpv"
  echo "（libepoxy-dev 通常也需要，多数桌面环境已带）"
  exit 1
fi
echo "    libmpv: OK ($(pkg-config --modversion mpv))"

echo "==> 预下载 mimalloc（media_kit Linux 构建用）..."
mkdir -p "$MIMALLOC_DIR"

need_download=1
if [ -f "$MIMALLOC_FILE" ]; then
  actual_md5="$(md5sum "$MIMALLOC_FILE" | awk '{print $1}')"
  if [ "$actual_md5" = "$MIMALLOC_MD5" ] && [ -s "$MIMALLOC_FILE" ]; then
    echo "    已存在且 MD5 正确: $MIMALLOC_FILE"
    need_download=0
  else
    echo "    文件损坏或不完整，重新下载..."
    rm -f "$MIMALLOC_FILE"
  fi
fi

if [ "$need_download" -eq 1 ]; then
  if [ -n "${https_proxy:-}" ] || [ -n "${http_proxy:-}" ]; then
    echo "    使用代理: ${https_proxy:-${http_proxy:-none}}"
  else
    echo "    提示: GitHub 较慢时可设置 https_proxy 后重试"
  fi
  curl -L --retry 3 --fail -o "$MIMALLOC_FILE" "$MIMALLOC_URL"
  actual_md5="$(md5sum "$MIMALLOC_FILE" | awk '{print $1}')"
  if [ "$actual_md5" != "$MIMALLOC_MD5" ]; then
    echo "MD5 校验失败: 期望 $MIMALLOC_MD5，实际 $actual_md5"
    exit 1
  fi
  echo "    下载完成: $MIMALLOC_FILE"
fi

echo "==> 依赖就绪，可执行: flutter run -d linux"
