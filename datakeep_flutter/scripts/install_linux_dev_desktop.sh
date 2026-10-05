#!/usr/bin/env bash
# 为 flutter run / 本地 bundle 安装用户级 .desktop + 图标，
# 让 Ubuntu/GNOME 任务栏能按 application-id（site.datakeep）显示图标。
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="site.datakeep"
DISPLAY_NAME="数据管理"
ICON_SRC="$APP_DIR/linux/icons"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"

mkdir -p "$APPS_DIR"
for size in 48 64 128 256 512; do
  src="$ICON_SRC/app_icon_${size}.png"
  [[ -f "$src" ]] || continue
  mkdir -p "$ICONS_DIR/${size}x${size}/apps"
  cp -f "$src" "$ICONS_DIR/${size}x${size}/apps/${APP_ID}.png"
done
# 默认尺寸兜底
if [[ -f "$ICON_SRC/app_icon.png" ]]; then
  mkdir -p "$ICONS_DIR/256x256/apps"
  cp -f "$ICON_SRC/app_icon.png" "$ICONS_DIR/256x256/apps/${APP_ID}.png"
fi

# Exec 指向现有 bundle（无则写占位，任务栏匹配仍靠 StartupWMClass / desktop 文件名）
EXEC_BIN=""
for cand in \
  "$APP_DIR/build/linux/x64/debug/bundle/datakeep_flutter" \
  "$APP_DIR/build/linux/x64/release/bundle/datakeep_flutter"; do
  if [[ -x "$cand" ]]; then
    EXEC_BIN="$cand"
    break
  fi
done
if [[ -z "$EXEC_BIN" ]]; then
  EXEC_BIN="$APP_DIR/build/linux/x64/debug/bundle/datakeep_flutter"
fi

cat > "$APPS_DIR/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${DISPLAY_NAME}
Comment=跨平台数据管理与文件同步
Exec=${EXEC_BIN}
Icon=${APP_ID}
Terminal=false
Categories=Utility;System;FileTransfer;
StartupWMClass=site.datakeep
StartupNotify=true
EOF

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q "$APPS_DIR" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f "$ICONS_DIR" 2>/dev/null || true
fi

echo "已安装开发用桌面入口: $APPS_DIR/${APP_ID}.desktop"
echo "图标主题: $ICONS_DIR/*/apps/${APP_ID}.png"
echo "重启应用后 Ubuntu 任务栏应显示「${DISPLAY_NAME}」图标。"
