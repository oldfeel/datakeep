#!/bin/bash

# MyData Flutter Android 客户端启动脚本
# 用途：启动 Flutter Android 应用
# 注意：Android 应用使用 AAR 中的 Go backend，无需在 PC 上启动后端服务

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${GREEN}🚀 MyData Android 客户端启动脚本${NC}"
echo "=================================="

# 检查 Flutter 是否安装
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter 未安装或未添加到 PATH${NC}"
    echo "请确保 Flutter 已安装并添加到环境变量"
    exit 1
fi

# 检查 Go 是否安装
if ! command -v go &> /dev/null; then
    echo -e "${RED}❌ Go 未安装或未添加到 PATH${NC}"
    echo "请确保 Go 已安装并添加到环境变量"
    exit 1
fi

# 检查 ADB 是否安装（用于检测 Android 设备）
if ! command -v adb &> /dev/null; then
    echo -e "${YELLOW}⚠️  ADB 未安装或未添加到 PATH${NC}"
    echo "ADB 用于检测 Android 设备，请确保 Android SDK Platform Tools 已安装"
    echo "如果没有安装，可以："
    echo "  - Ubuntu/Debian: sudo apt install android-tools-adb"
    echo "  - 或从 https://developer.android.com/studio/releases/platform-tools 下载"
fi

# 提示：Android 应用使用 AAR 中的 Go backend
echo -e "${GREEN}ℹ️  Android 应用使用 AAR 中的 Go backend${NC}"
echo -e "${YELLOW}   后端服务将在应用内自动启动，无需在 PC 上启动${NC}"

# 检查并安装 Flutter 依赖
echo -e "\n${BLUE}📦 检查 Flutter 依赖...${NC}"
flutter pub get

# 检查 Android 设备/模拟器
echo -e "\n${BLUE}📱 检查 Android 设备...${NC}"
if command -v adb &> /dev/null; then
    # 启动 ADB 服务器
    adb start-server > /dev/null 2>&1 || true
    
    # 检查连接的设备
    DEVICES=$(adb devices | grep -v "List" | grep "device$" | wc -l)
    if [ "$DEVICES" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  未检测到 Android 设备或模拟器${NC}"
        echo "请确保："
        echo "  1. Android 设备已通过 USB 连接并启用 USB 调试"
        echo "  2. 或 Android 模拟器已启动"
        echo ""
        echo "正在检查模拟器..."
        if command -v emulator &> /dev/null; then
            echo -e "${YELLOW}提示: 可以使用以下命令启动模拟器:${NC}"
            echo "  emulator -avd <AVD名称>"
        fi
        echo ""
        read -p "是否继续尝试启动应用？(y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo -e "${GREEN}✅ 检测到 $DEVICES 个 Android 设备${NC}"
        adb devices
    fi
else
    echo -e "${YELLOW}⚠️  ADB 未安装，无法检测设备${NC}"
    echo "将直接尝试启动应用"
fi

# 启动 Flutter Android 应用
echo -e "\n${BLUE}🚀 启动 Flutter Android 应用...${NC}"
echo -e "${YELLOW}提示: 按 Ctrl+C 可停止应用${NC}"
echo -e "${YELLOW}注意: Android 应用使用 AAR 中的 Go backend，后端服务在应用内运行${NC}"
echo ""

# 使用 flutter run 启动 Android 应用
# 获取第一个 Android 设备的 ID
ANDROID_DEVICE_ID=""
if command -v adb &> /dev/null && [ "$DEVICES" -gt 0 ]; then
    # 获取第一个设备的 ID
    ANDROID_DEVICE_ID=$(adb devices | grep -v "List" | grep "device$" | head -1 | awk '{print $1}')
    if [ -n "$ANDROID_DEVICE_ID" ]; then
        echo -e "${GREEN}使用设备: $ANDROID_DEVICE_ID${NC}"
        flutter run -d "$ANDROID_DEVICE_ID"
    else
        echo -e "${YELLOW}无法获取设备 ID，让 Flutter 自动选择设备${NC}"
        flutter run
    fi
else
    # 如果没有检测到设备，让 Flutter 自动选择或提示用户
    echo -e "${YELLOW}未检测到设备，让 Flutter 自动选择或提示选择设备${NC}"
    flutter run
fi

