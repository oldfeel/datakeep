#!/usr/bin/env bash
# 打包 .deb：默认兼容 Ubuntu（写入 /usr/share 桌面入口）；可选纯 deepin 商店规范包
#
# 用法:
#   ./scripts/package_deepin_deb.sh              # Ubuntu+deepin 目录结构（本机/通用）
#   ./scripts/package_deepin_deb.sh --build      # 先 flutter build linux --release 再打包
#   ./scripts/package_deepin_deb.sh --deepin     # 仅 /opt/apps（投递 deepin 社区商店）
#
# 产物: dist/site.datakeep_<version>_amd64.deb

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/datakeep_flutter"
DIST="$ROOT/dist"
APPID="site.datakeep"
DISPLAY_NAME="数据管理"
DO_BUILD=0
# 0=兼容 Ubuntu（额外写 /usr/share）；1=仅 /opt/apps，供 deepin 商店
DEEPIN_STORE=0

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
log()  { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

for arg in "$@"; do
  case "$arg" in
    --build|-b) DO_BUILD=1 ;;
    --deepin|--store) DEEPIN_STORE=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      err "未知参数: $arg"
      exit 1
      ;;
  esac
done

command -v dpkg-deb >/dev/null || { err "需要 dpkg-deb"; exit 1; }
command -v fakeroot >/dev/null || { err "需要 fakeroot"; exit 1; }

read_version() {
  local v
  v="$(grep -E '^version:' "$APP_DIR/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d '"' | tr -d "'")"
  # 0.2.5+25 → 0.2.5（deb Version）
  echo "${v%%+*}"
}

ensure_syncthing() {
  if [[ -x "$APP_DIR/bin/syncthing" ]]; then
    return 0
  fi
  log "准备 syncthing 二进制…"
  bash "$ROOT/scripts/build_desktop_syncthing.sh"
}

if [[ "$DO_BUILD" -eq 1 ]]; then
  ensure_syncthing
  log "flutter build linux --release…"
  (
    cd "$APP_DIR"
    flutter pub get
    flutter build linux --release
  )
fi

VERSION="$(read_version)"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
BUNDLE="$APP_DIR/build/linux/x64/release/bundle"
if [[ ! -d "$BUNDLE" ]]; then
  BUNDLE="$(find "$APP_DIR/build/linux" -type d -path '*/release/bundle' 2>/dev/null | head -1 || true)"
fi
[[ -d "$BUNDLE" ]] || {
  err "未找到 Linux bundle。请先: ./scripts/package_deepin_deb.sh --build"
  exit 1
}
[[ -x "$BUNDLE/datakeep_flutter" ]] || {
  err "bundle 中缺少可执行文件 datakeep_flutter"
  exit 1
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

APP_ROOT="$STAGE/opt/apps/$APPID"
FILES="$APP_ROOT/files"
mkdir -p "$APP_ROOT/entries/applications"
mkdir -p "$APP_ROOT/entries/icons/hicolor/48x48/apps"
mkdir -p "$APP_ROOT/entries/icons/hicolor/64x64/apps"
mkdir -p "$APP_ROOT/entries/icons/hicolor/128x128/apps"
mkdir -p "$APP_ROOT/entries/icons/hicolor/256x256/apps"
mkdir -p "$APP_ROOT/entries/icons/hicolor/512x512/apps"
mkdir -p "$STAGE/DEBIAN"
mkdir -p "$FILES"

log "复制 Flutter bundle → files/"
cp -a "$BUNDLE"/. "$FILES/"

# 确保捆绑 syncthing
mkdir -p "$FILES/data/bin"
if [[ -x "$APP_DIR/bin/syncthing" ]]; then
  cp -f "$APP_DIR/bin/syncthing" "$FILES/data/bin/syncthing"
  chmod 755 "$FILES/data/bin/syncthing"
  ok "已放入 data/bin/syncthing"
elif [[ -x "$FILES/data/bin/syncthing" ]]; then
  ok "bundle 已含 syncthing"
else
  warn "未找到 syncthing；包可安装但首次运行可能需系统已安装 syncthing"
fi

# 旧 Go 后端已停维，避免误带入
rm -f "$FILES/data/bin/datakeep_backend"

# 启动包装：固定工作目录，避免相对路径资源找不到
mkdir -p "$FILES/bin"
cat > "$FILES/bin/datakeep-launcher" <<EOF
#!/bin/bash
set -euo pipefail
# 经 /usr/bin/datakeep 符号链接启动时，\$0 是 /usr/bin/datakeep，需解析真实路径
SCRIPT="\$(readlink -f "\$0")"
HERE="\$(cd "\$(dirname "\$SCRIPT")/.." && pwd)"
cd "\$HERE"
export LD_LIBRARY_PATH="\$HERE/lib:\${LD_LIBRARY_PATH:-}"
exec "\$HERE/datakeep_flutter" "\$@"
EOF
chmod 755 "$FILES/bin/datakeep-launcher"

# 图标（opt 内，deepin 用）
ICON_SRC="$APP_DIR/linux/icons"
copy_icon() {
  local size="$1" src="$2"
  if [[ -f "$src" ]]; then
    cp -f "$src" "$APP_ROOT/entries/icons/hicolor/${size}x${size}/apps/${APPID}.png"
  fi
}
copy_icon 48  "$ICON_SRC/app_icon_48.png"
copy_icon 64  "$ICON_SRC/app_icon_64.png"
copy_icon 128 "$ICON_SRC/app_icon_128.png"
copy_icon 256 "$ICON_SRC/app_icon_256.png"
copy_icon 512 "$ICON_SRC/app_icon_512.png"

DESKTOP_BODY="[Desktop Entry]
Version=1.0
Type=Application
Name=${DISPLAY_NAME}
Comment=跨平台数据管理与文件同步
Exec=/opt/apps/${APPID}/files/bin/datakeep-launcher
Icon=${APPID}
Terminal=false
Categories=Utility;System;FileTransfer;
StartupWMClass=site.datakeep
"

# desktop（opt 内）
printf '%s\n' "$DESKTOP_BODY" > "$APP_ROOT/entries/applications/${APPID}.desktop"

# Ubuntu / 通用：系统菜单与图标主题路径
if [[ "$DEEPIN_STORE" -eq 0 ]]; then
  log "写入 Ubuntu 兼容路径 (/usr/share/applications、icons)…"
  mkdir -p "$STAGE/usr/share/applications"
  printf '%s\n' "$DESKTOP_BODY" > "$STAGE/usr/share/applications/${APPID}.desktop"
  for size in 48 64 128 256 512; do
    src="$ICON_SRC/app_icon_${size}.png"
    if [[ -f "$src" ]]; then
      mkdir -p "$STAGE/usr/share/icons/hicolor/${size}x${size}/apps"
      cp -f "$src" "$STAGE/usr/share/icons/hicolor/${size}x${size}/apps/${APPID}.png"
    fi
  done
  # 可选：PATH 里能直接打命令名
  mkdir -p "$STAGE/usr/bin"
  ln -sfn "/opt/apps/${APPID}/files/bin/datakeep-launcher" "$STAGE/usr/bin/datakeep"
  ok "已加入 usr/share 桌面入口与 /usr/bin/datakeep"

  cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
fi
EOF
  cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/bash
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
fi
EOF
  chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"
else
  ok "deepin 商店模式：仅 /opt/apps（无 /usr、无 postinst）"
fi

# deepin / UOS info
cat > "$APP_ROOT/info" <<EOF
{
  "appid": "${APPID}",
  "name": "${DISPLAY_NAME}",
  "version": "${VERSION}",
  "arch": ["${ARCH}"],
  "permissions": {
    "autostart": false,
    "notification": true,
    "trayicon": true,
    "clipboard": true,
    "account": false,
    "bluetooth": false,
    "camera": false,
    "audio_record": false,
    "installed_apps": false
  }
}
EOF

# Installed-Size（KB）；deepin 模式无 usr
INSTALLED_SIZE=0
if [[ -d "$STAGE/opt" ]]; then
  INSTALLED_SIZE=$((INSTALLED_SIZE + $(du -sk "$STAGE/opt" | awk '{print $1}')))
fi
if [[ -d "$STAGE/usr" ]]; then
  INSTALLED_SIZE=$((INSTALLED_SIZE + $(du -sk "$STAGE/usr" | awk '{print $1}')))
fi

cat > "$STAGE/DEBIAN/control" <<EOF
Package: ${APPID}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: DataKeep <noreply@datakeep.site>
Homepage: https://datakeep.site
Description: ${DISPLAY_NAME} - 跨平台数据管理与文件同步
 基于 Syncthing 的跨平台文件同步客户端，支持设备配对、文件夹共享与文件浏览。
Depends: libgtk-3-0, libblkid1, liblzma5
EOF

# 权限
find "$STAGE/opt" -type d -exec chmod 755 {} \;
find "$STAGE/opt" -type f -exec chmod 644 {} \;
if [[ -d "$STAGE/usr" ]]; then
  find "$STAGE/usr" -type d -exec chmod 755 {} \;
  find "$STAGE/usr" -type f -exec chmod 644 {} \;
  # /usr/bin/datakeep 是符号链接，保持可执行语义
  chmod 755 "$STAGE/usr/bin" 2>/dev/null || true
fi
chmod 755 "$FILES/datakeep_flutter" "$FILES/bin/datakeep-launcher"
[[ -f "$FILES/data/bin/syncthing" ]] && chmod 755 "$FILES/data/bin/syncthing"
find "$FILES/lib" -type f -name '*.so*' -exec chmod 755 {} \; 2>/dev/null || true
chmod 755 "$STAGE/DEBIAN"
chmod 644 "$STAGE/DEBIAN/control"
[[ -f "$STAGE/DEBIAN/postinst" ]] && chmod 755 "$STAGE/DEBIAN/postinst"
[[ -f "$STAGE/DEBIAN/postrm" ]] && chmod 755 "$STAGE/DEBIAN/postrm"

mkdir -p "$DIST"
OUT="$DIST/${APPID}_${VERSION}_${ARCH}.deb"
if [[ "$DEEPIN_STORE" -eq 1 ]]; then
  OUT="$DIST/${APPID}_${VERSION}_${ARCH}-deepin.deb"
fi
log "打包 $OUT …"
fakeroot dpkg-deb --build -Zxz "$STAGE" "$OUT"
ok "已生成: $OUT"
ls -lh "$OUT"
echo
echo "安装: sudo dpkg -i $OUT"
echo "启动: datakeep   或  应用菜单搜索「${DISPLAY_NAME}」"
echo "卸载: sudo dpkg -r ${APPID}"
if [[ "$DEEPIN_STORE" -eq 0 ]]; then
  echo "投递 deepin 商店请用: ./scripts/package_deepin_deb.sh --deepin"
else
  echo "商店投递: https://appdelivery.deepin.org.cn"
fi
