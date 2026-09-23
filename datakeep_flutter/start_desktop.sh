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

# NVIDIA + CEF：勿用 FLUTTER_LINUX_RENDERER=software（CEF 纹理会白屏）。
# 改用 Mesa 软 GL，保留 OpenGL 合成路径。
if [[ "$PLATFORM" == "linux" ]]; then
  if [[ "${FLUTTER_LINUX_RENDERER:-}" == "software" ]]; then
    unset FLUTTER_LINUX_RENDERER
    echo -e "${YELLOW}⚠️  已取消 FLUTTER_LINUX_RENDERER=software（会导致应用页白屏）${NC}"
  fi
  if [[ -z "${LIBGL_ALWAYS_SOFTWARE:-}" ]] && [[ -z "${DATAKEEP_ALLOW_NVIDIA_GL:-}" ]]; then
    if [[ -r /proc/driver/nvidia/version ]] || grep -q '^nvidia' /proc/modules 2>/dev/null; then
      export LIBGL_ALWAYS_SOFTWARE=1
      echo -e "${YELLOW}⚠️  检测到 NVIDIA：已设 LIBGL_ALWAYS_SOFTWARE=1（防 CEF 闪退，略影响性能）${NC}"
    fi
  fi
fi

# 关闭终端（SIGHUP）/ Ctrl+C 时兜底停掉应用窗口与 detached 的 syncthing
# （Dart 侧也会处理信号与窗口关闭；此处应对 flutter run 被终端强杀、钩子来不及跑的情况）
_cleanup_desktop() {
  if [[ "$PLATFORM" == "linux" ]]; then
    # Linux comm 仅 15 字符，-x 匹配不可靠；按 bundle 路径杀本次工程进程
    pkill -f "${SCRIPT_DIR}/build/linux/.*/bundle/datakeep_flutter" 2>/dev/null || true
    pkill -x syncthing 2>/dev/null || true
  elif [[ "$PLATFORM" == "macos" ]]; then
    pkill -f "${SCRIPT_DIR}/build/macos/.*/datakeep_flutter" 2>/dev/null || true
    pkill -x syncthing 2>/dev/null || true
  fi
}
trap _cleanup_desktop EXIT INT TERM HUP

flutter run -d "$PLATFORM"
_flutter_status=$?
trap - EXIT INT TERM HUP
_cleanup_desktop
exit "$_flutter_status"
