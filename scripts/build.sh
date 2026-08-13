#!/usr/bin/env bash
# DataKeep 多平台安装包构建
#
# 用法:
#   ./scripts/build.sh              # 构建当前系统能编的全部目标
#   ./scripts/build.sh all          # 同上
#   ./scripts/build.sh android linux
#   ./scripts/build.sh --help
#
# 产物目录: dist/
#   datakeep-<version>-android.apk
#   datakeep-<version>-linux-x64.tar.gz
#   datakeep-<version>-windows-x64.zip   （需在 Windows 上构建）
#   datakeep-<version>-macos.zip        （需在 macOS 上构建）
#
# 说明:
#   - Flutter 官方不支持跨 OS 交叉编译桌面端（Linux 编不出 Windows/macOS 安装包）
#   - Android 可在 Linux / macOS / Windows 上构建（需 Android SDK + syncthing_core AAR）
#   - 桌面端依赖系统已安装的 syncthing；移动端内嵌 syncthing_core
#   - 也可用 GitHub Actions（公开仓免费）: 仓库 → Actions → Build packages
#     或: gh workflow run build.yml

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/datakeep_flutter"
DIST="$ROOT/dist"
HOST="$(uname -s | tr '[:upper:]' '[:lower:]')"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \?//'
  exit 0
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "缺少命令: $1"
    return 1
  }
}

read_version() {
  local line
  line="$(grep -E '^version:' "$APP_DIR/pubspec.yaml" | head -1 | awk '{print $2}')"
  # 1.0.0+1 → 1.0.0
  echo "${line%%+*}"
}

VERSION="$(read_version)"
STAMP="$(date +%Y%m%d)"
ARTIFACTS=()
SKIPPED=()
FAILED=()

can_build_android() {
  need_cmd flutter || return 1
  # SDK 由 flutter doctor / local.properties 提供；这里只做轻量检查
  return 0
}

can_build_linux() {
  [[ "$HOST" == "linux" ]] || return 1
  need_cmd flutter || return 1
}

can_build_windows() {
  # Git Bash / MSYS / Cygwin 下 uname 常为 mingw* / msys / cygwin
  case "$HOST" in
    mingw*|msys*|cygwin*|windows*) ;;
    *) return 1 ;;
  esac
  need_cmd flutter || return 1
}

can_build_macos() {
  [[ "$HOST" == "darwin" ]] || return 1
  need_cmd flutter || return 1
}

prepare() {
  mkdir -p "$DIST"
  need_cmd flutter
  log "Flutter: $(flutter --version 2>/dev/null | head -1)"
  log "版本: $VERSION  宿主: $HOST"
  cd "$APP_DIR"
  log "flutter pub get"
  flutter pub get
}

build_android() {
  log "构建 Android APK（先编译 syncthing_core AAR）…"
  if [[ ! -f "$APP_DIR/syncthing_core/Makefile" ]]; then
    err "找不到 syncthing_core/Makefile"
    return 1
  fi
  make -C "$APP_DIR/syncthing_core" android
  flutter build apk --release

  local src="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
  local out="$DIST/datakeep-${VERSION}-android.apk"
  cp -f "$src" "$out"
  # 可选带日期副本，便于留档
  cp -f "$src" "$DIST/datakeep-${VERSION}-${STAMP}-android.apk"
  ARTIFACTS+=("$out")
  ok "Android → $out"
}

build_linux() {
  log "构建 Linux release…"
  flutter build linux --release

  local bundle="$APP_DIR/build/linux/x64/release/bundle"
  if [[ ! -d "$bundle" ]]; then
    # 少数环境可能是 arm64
    bundle="$(find "$APP_DIR/build/linux" -type d -path '*/release/bundle' | head -1)"
  fi
  [[ -d "$bundle" ]] || {
    err "未找到 Linux bundle"
    return 1
  }

  local out="$DIST/datakeep-${VERSION}-linux-x64.tar.gz"
  local stage
  stage="$(mktemp -d)"
  mkdir -p "$stage/datakeep-${VERSION}-linux"
  cp -a "$bundle"/. "$stage/datakeep-${VERSION}-linux/"
  tar -C "$stage" -czf "$out" "datakeep-${VERSION}-linux"
  rm -rf "$stage"

  ARTIFACTS+=("$out")
  ok "Linux → $out"
  warn "运行前请确保系统已安装 syncthing，并具备 GTK 等桌面依赖"
}

build_windows() {
  log "构建 Windows release…"
  flutter build windows --release

  local release
  release="$(find "$APP_DIR/build/windows" -type d -path '*/runner/Release' | head -1)"
  [[ -d "$release" ]] || {
    err "未找到 Windows Release 目录"
    return 1
  }

  local out="$DIST/datakeep-${VERSION}-windows-x64.zip"
  if command -v zip >/dev/null 2>&1; then
    local stage
    stage="$(mktemp -d)"
    mkdir -p "$stage/datakeep-${VERSION}-windows"
    cp -a "$release"/. "$stage/datakeep-${VERSION}-windows/"
    (cd "$stage" && zip -qr "$out" "datakeep-${VERSION}-windows")
    rm -rf "$stage"
  else
    # PowerShell Compress-Archive
    powershell.exe -NoProfile -Command \
      "Compress-Archive -Path '$release\\*' -DestinationPath '$out' -Force"
  fi
  ARTIFACTS+=("$out")
  ok "Windows → $out"
  warn "运行前请确保系统已安装 syncthing；首次运行 CEF 体积较大"
}

build_macos() {
  log "构建 macOS release…"
  # CEF / Pod 可能较久；部署目标由 Podfile 约束
  flutter build macos --release

  local app
  app="$(find "$APP_DIR/build/macos" -maxdepth 4 -name '*.app' -type d | head -1)"
  [[ -d "$app" ]] || {
    err "未找到 .app"
    return 1
  }

  local out="$DIST/datakeep-${VERSION}-macos.zip"
  local stage
  stage="$(mktemp -d)"
  cp -a "$app" "$stage/"
  (cd "$stage" && zip -qry "$out" "$(basename "$app")")
  rm -rf "$stage"

  ARTIFACTS+=("$out")
  ok "macOS → $out"
  warn "公证/DMG 未自动处理；分发到其他 Mac 可能还需 codesign / notarize"
}

try_target() {
  local t="$1"
  case "$t" in
    android)
      if can_build_android; then
        build_android || FAILED+=("android")
      else
        SKIPPED+=("android(环境不足)")
      fi
      ;;
    linux)
      if can_build_linux; then
        build_linux || FAILED+=("linux")
      else
        SKIPPED+=("linux(需在 Linux 上构建)")
      fi
      ;;
    windows)
      if can_build_windows; then
        build_windows || FAILED+=("windows")
      else
        SKIPPED+=("windows(需在 Windows 上构建)")
      fi
      ;;
    macos|mac|osx)
      if can_build_macos; then
        build_macos || FAILED+=("macos")
      else
        SKIPPED+=("macos(需在 macOS 上构建)")
      fi
      ;;
    *)
      err "未知目标: $t"
      usage
      ;;
  esac
}

# ── main ─────────────────────────────────────────────────────

TARGETS=()
for arg in "$@"; do
  case "$arg" in
    -h|--help|help) usage ;;
    all) TARGETS=(android linux windows macos) ;;
    *) TARGETS+=("$arg") ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=(android linux windows macos)
fi

prepare

for t in "${TARGETS[@]}"; do
  echo
  try_target "$t"
done

echo
echo "======== 构建结果 ========"
if [[ ${#ARTIFACTS[@]} -gt 0 ]]; then
  ok "产物 (${#ARTIFACTS[@]}):"
  for f in "${ARTIFACTS[@]}"; do
    ls -lh "$f" | awk '{print "  " $5 "\t" $9}'
  done
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  warn "跳过: ${SKIPPED[*]}"
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  err "失败: ${FAILED[*]}"
  exit 1
fi
if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
  warn "没有生成任何安装包（当前宿主可能无法构建所选目标）"
  exit 2
fi
ok "完成。输出目录: $DIST"
