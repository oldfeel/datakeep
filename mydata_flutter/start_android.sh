#!/bin/bash

# MyData Flutter Android 客户端启动脚本
# 用途：启动 Go 后端服务，然后启动 Flutter Android 应用
# 注意：Android 应用需要通过局域网访问后端服务

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

# 检查后端服务是否已经在运行
echo -e "${YELLOW}🔍 检查后端服务状态...${NC}"
if curl -k -s https://localhost:8443/api/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ 后端服务已在运行${NC}"
    BACKEND_RUNNING=true
else
    echo -e "${YELLOW}⚠️  后端服务未运行，准备启动...${NC}"
    BACKEND_RUNNING=false
fi

# 启动后端服务（如果未运行）
if [ "$BACKEND_RUNNING" = false ]; then
    echo -e "\n${BLUE}🔧 启动 Go 后端服务...${NC}"
    cd backend/cmd
    
    # 检查是否有编译好的可执行文件
    if [ -f "mydata_backend" ]; then
        echo -e "${YELLOW}使用已编译的可执行文件...${NC}"
        ./mydata_backend &
        BACKEND_PID=$!
    else
        echo -e "${YELLOW}编译并运行后端服务...${NC}"
        go run main.go &
        BACKEND_PID=$!
    fi
    
    cd ../..
    
    # 等待后端服务启动
    echo -e "${YELLOW}⏳ 等待后端服务启动...${NC}"
    for i in {1..30}; do
        if curl -k -s https://localhost:8443/api/health > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 后端服务已启动${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}❌ 后端服务启动超时${NC}"
            kill $BACKEND_PID 2>/dev/null || true
            exit 1
        fi
        sleep 1
    done
    
    # 设置退出时清理后端进程
    trap "echo -e '\n${YELLOW}🛑 停止后端服务...${NC}'; kill $BACKEND_PID 2>/dev/null || true; exit" INT TERM
fi

# 获取本机 IP 地址（用于 Android 设备访问）
echo -e "\n${BLUE}🌐 获取本机 IP 地址...${NC}"
LOCAL_IP=$(hostname -I | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then
    # 尝试其他方法获取 IP
    LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || echo "")
fi

if [ -z "$LOCAL_IP" ]; then
    echo -e "${YELLOW}⚠️  无法自动获取 IP 地址${NC}"
    echo "请手动设置 Android 应用的 API 地址为: https://<你的IP>:8443/api"
else
    echo -e "${GREEN}✅ 本机 IP 地址: $LOCAL_IP${NC}"
    echo -e "${YELLOW}📱 Android 应用将使用: https://$LOCAL_IP:8443/api${NC}"
    echo -e "${YELLOW}   如果 Android 设备无法连接，请检查防火墙设置${NC}"
fi

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
            if [ "$BACKEND_RUNNING" = false ]; then
                echo -e "${YELLOW}🛑 停止后端服务...${NC}"
                kill $BACKEND_PID 2>/dev/null || true
            fi
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
echo -e "${YELLOW}提示: 按 Ctrl+C 可同时停止前端和后端服务${NC}"
echo -e "${YELLOW}注意: Android 应用需要通过局域网访问后端 (https://$LOCAL_IP:8443/api)${NC}"
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

# 如果后端是我们启动的，退出时清理
if [ "$BACKEND_RUNNING" = false ]; then
    echo -e "\n${YELLOW}🛑 停止后端服务...${NC}"
    kill $BACKEND_PID 2>/dev/null || true
fi

