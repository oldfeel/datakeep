#!/usr/bin/env bash
# 启动指定 Android 模拟器的小工具脚本
# 用法: scripts/start_avd.sh <AVD名称> [其他 emulator 参数]

set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
EMULATOR_BIN="${EMULATOR_BIN:-${ANDROID_SDK_ROOT}/emulator/emulator}"
DEFAULT_AVD="${DEFAULT_AVD:-Pixel_Tablet}"
DEFAULT_AVD_ARGS="${DEFAULT_AVD_ARGS:-"-no-snapshot-load -gpu swiftshader_indirect"}"

read -r -a DEFAULT_ARGS <<< "$DEFAULT_AVD_ARGS"

if [[ ! -x "$EMULATOR_BIN" ]]; then
  echo "未找到 emulator 可执行文件: $EMULATOR_BIN" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "未提供 AVD 名称，默认启动: ${DEFAULT_AVD}"
  AVD_NAME="$DEFAULT_AVD"
else
  AVD_NAME="$1"
  shift || true
fi

if [[ ${#DEFAULT_ARGS[@]} -gt 0 ]]; then
  echo "默认附加参数: ${DEFAULT_ARGS[*]}"
fi

echo "正在启动模拟器: $AVD_NAME"
"$EMULATOR_BIN" -avd "$AVD_NAME" "${DEFAULT_ARGS[@]}" "$@"

