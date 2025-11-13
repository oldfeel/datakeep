#!/bin/bash

# MyData Flutter 桌面客户端启动脚本
# 用途：启动 Go 后端服务，然后启动 Flutter 桌面应用

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

echo -e "${GREEN}🚀 MyData 桌面客户端启动脚本${NC}"
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
    
    # 设置退出时清理后端进程
    trap "echo -e '\n${YELLOW}🛑 停止后端服务...${NC}'; kill $BACKEND_PID 2>/dev/null || true; exit" INT TERM
fi

# 检查并安装 Flutter 依赖
echo -e "\n${BLUE}📦 检查 Flutter 依赖...${NC}"
flutter pub get

# 检测可用的桌面平台
echo -e "\n${BLUE}🖥️  检测可用的桌面平台...${NC}"
AVAILABLE_PLATFORMS=""

if flutter devices | grep -q "linux"; then
    AVAILABLE_PLATFORMS="$AVAILABLE_PLATFORMS linux"
fi

if flutter devices | grep -q "windows"; then
    AVAILABLE_PLATFORMS="$AVAILABLE_PLATFORMS windows"
fi

if flutter devices | grep -q "macos"; then
    AVAILABLE_PLATFORMS="$AVAILABLE_PLATFORMS macos"
fi

if [ -z "$AVAILABLE_PLATFORMS" ]; then
    echo -e "${RED}❌ 未检测到可用的桌面平台${NC}"
    echo "请确保已安装桌面平台支持："
    echo "  - Linux: flutter config --enable-linux-desktop"
    echo "  - Windows: flutter config --enable-windows-desktop"
    echo "  - macOS: flutter config --enable-macos-desktop"
    exit 1
fi

# 选择平台（优先使用 Linux）
PLATFORM="linux"
if echo "$AVAILABLE_PLATFORMS" | grep -q "linux"; then
    PLATFORM="linux"
elif echo "$AVAILABLE_PLATFORMS" | grep -q "windows"; then
    PLATFORM="windows"
elif echo "$AVAILABLE_PLATFORMS" | grep -q "macos"; then
    PLATFORM="macos"
fi

echo -e "${GREEN}✅ 使用平台: $PLATFORM${NC}"

# 启动 Flutter 应用
echo -e "\n${BLUE}🚀 启动 Flutter 桌面应用...${NC}"
echo -e "${YELLOW}提示: 按 Ctrl+C 可同时停止前端和后端服务${NC}"
echo ""

flutter run -d $PLATFORM

# 如果后端是我们启动的，退出时清理
if [ "$BACKEND_RUNNING" = false ]; then
    echo -e "\n${YELLOW}🛑 停止后端服务...${NC}"
    kill $BACKEND_PID 2>/dev/null || true
fi

