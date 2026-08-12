#!/bin/bash

# DataKeep Flutter 桌面客户端启动脚本
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

echo -e "${GREEN}🚀 DataKeep 桌面客户端启动脚本${NC}"
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

# 第一步：编译生成可执行文件
echo -e "\n${BLUE}📦 第一步：编译生成可执行文件${NC}"
echo "=============================="

# 确保使用正确的 Go 版本
export PATH=/usr/local/go/bin:$PATH

# 检查 backend 是否已编译
BACKEND_BINARY="$SCRIPT_DIR/bin/datakeep_backend"
if [ ! -f "$BACKEND_BINARY" ]; then
    echo -e "${YELLOW}Backend 未编译，开始编译...${NC}"
    
    # 检查 backend 目录
    if [ ! -d "$SCRIPT_DIR/backend" ]; then
        echo -e "${RED}❌ backend 目录不存在${NC}"
        exit 1
    fi
    
    # 编译 backend
    cd "$SCRIPT_DIR/backend"
    go build -o cmd/datakeep_backend ./cmd
    if [ -f "cmd/datakeep_backend" ]; then
        mkdir -p "$SCRIPT_DIR/bin"
        cp cmd/datakeep_backend "$BACKEND_BINARY"
        chmod +x "$BACKEND_BINARY"
        echo -e "${GREEN}✅ Backend 编译成功: $BACKEND_BINARY${NC}"
    else
        echo -e "${RED}❌ Backend 编译失败${NC}"
        exit 1
    fi
    cd "$SCRIPT_DIR"
else
    echo -e "${GREEN}✅ Backend 已编译: $BACKEND_BINARY${NC}"
fi

# 检查 Syncthing 是否已编译
SYNCTHING_BINARY="$SCRIPT_DIR/bin/syncthing"
SYNCTHING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/syncthing"

if [ ! -f "$SYNCTHING_BINARY" ]; then
    echo -e "${YELLOW}Syncthing 未编译，开始编译...${NC}"
    
    # 检查 syncthing 目录
    if [ ! -d "$SYNCTHING_DIR" ]; then
        echo -e "${RED}❌ Syncthing 目录不存在: $SYNCTHING_DIR${NC}"
        exit 1
    fi
    
    # 编译 Syncthing
    cd "$SYNCTHING_DIR"
    if [ ! -f "build.go" ]; then
        echo -e "${RED}❌ build.go 不存在${NC}"
        exit 1
    fi
    
    mkdir -p "$SCRIPT_DIR/bin"
    go run build.go -version "v1.28.1-datakeep" -no-upgrade build syncthing
    
    if [ -f "syncthing" ]; then
        mv syncthing "$SYNCTHING_BINARY"
        chmod +x "$SYNCTHING_BINARY"
        echo -e "${GREEN}✅ Syncthing 编译成功: $SYNCTHING_BINARY${NC}"
    else
        echo -e "${RED}❌ Syncthing 编译失败${NC}"
        exit 1
    fi
    cd "$SCRIPT_DIR"
else
    echo -e "${GREEN}✅ Syncthing 已编译: $SYNCTHING_BINARY${NC}"
fi

echo -e "${GREEN}✅ 可执行文件准备完成${NC}"
echo -e "${YELLOW}ℹ️  Backend 服务将由 Flutter 应用自动启动${NC}"

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

