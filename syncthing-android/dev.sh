#!/bin/bash

# 设置错误时退出
set -e

# 显示执行的命令
set -x

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 检查是否需要重新编译
REBUILD=false
if [ "$1" = "--rebuild" ] || [ "$1" = "-r" ]; then
    REBUILD=true
fi

# 检查 jniLibs 目录是否存在且不为空
JNI_DIR="app/src/main/jniLibs"
if [ ! -d "$JNI_DIR" ] || [ -z "$(ls -A $JNI_DIR/*/libsyncthing.so 2>/dev/null)" ]; then
    echo "未找到编译好的库文件，开始编译..."
    REBUILD=true
fi

# 如果需要重新编译
if [ "$REBUILD" = true ]; then
    echo "编译 syncthing 库..."
    cd lib_build
    go run main.go
    cd ..
fi

# 编译 debug APK
echo "编译 debug APK..."
./gradlew assembleDebug

# 查找生成的 APK 文件
APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK_PATH" ]; then
    echo "错误：找不到 APK 文件：$APK_PATH"
    exit 1
fi

# 检查是否有设备连接
DEVICES=$(adb devices | grep -v "List" | grep -v "^$" | wc -l)
if [ "$DEVICES" -eq 0 ]; then
    echo "错误：没有找到已连接的设备"
    echo "请确保："
    echo "1. 已启用 USB 调试"
    echo "2. 设备已通过 USB 连接"
    echo "3. 已在设备上允许 USB 调试"
    exit 1
fi

# 安装 APK
echo "安装 APK..."
adb install -r "$APK_PATH"

# 检查应用是否已安装
echo "检查应用状态..."
adb shell pm list packages | grep syncthing
adb shell dumpsys package com.nutomic.syncthingandroid.debug

# 启动应用
echo "启动应用..."
adb shell am start -n com.nutomic.syncthingandroid.debug/com.nutomic.syncthingandroid.activities.FirstStartActivity

# 检查应用是否正在运行
echo "检查应用运行状态..."
adb shell dumpsys activity activities | grep -A 5 "com.nutomic.syncthingandroid.debug"

# 如果应用没有启动，尝试强制停止后重新启动
echo "如果应用没有启动，尝试重新启动..."
adb shell am force-stop com.nutomic.syncthingandroid.debug
sleep 1
adb shell am start -n com.nutomic.syncthingandroid.debug/com.nutomic.syncthingandroid.activities.FirstStartActivity

echo "完成！"
echo "APK 已安装到设备上并启动"
echo "APK 文件位置：$APK_PATH"

# 显示使用说明
echo ""
echo "使用说明："
echo "1. 直接运行 ./dev.sh 将只编译 APK 并安装（如果库文件已存在）"
echo "2. 运行 ./dev.sh --rebuild 或 ./dev.sh -r 将重新编译库文件和 APK" 