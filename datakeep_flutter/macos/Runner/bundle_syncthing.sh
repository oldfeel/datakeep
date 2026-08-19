#!/bin/bash
# 将 datakeep_flutter/bin/syncthing 打入 .app（与 Linux data/bin/syncthing 同级用途）
set -euo pipefail

SYNCTHING_SRC="${SRCROOT}/../bin/syncthing"
APP_RESOURCES="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/bin"

if [[ ! -f "$SYNCTHING_SRC" ]]; then
  echo "warning: $SYNCTHING_SRC 不存在，跳过 Syncthing 打包（请先运行 scripts/build_desktop_syncthing.sh）"
  exit 0
fi

mkdir -p "$APP_RESOURCES"
cp -f "$SYNCTHING_SRC" "$APP_RESOURCES/"
chmod +x "$APP_RESOURCES/syncthing"
echo "Bundled Syncthing → $APP_RESOURCES/syncthing"
