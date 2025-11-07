#!/bin/bash

# MyData Flutter 编译安装脚本
# 用途：编译 Flutter 应用并安装到 Android 设备
# 用法: ./local.sh [debug|release|profile|run]
#   - debug: 编译 debug APK 并安装（默认）
#   - release: 编译 release APK 并安装
#   - profile: 编译 profile APK 并安装
#   - run: 运行 flutter run（支持热重载）

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 设置 Flutter 镜像源（中国用户）
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 设置 Flutter 路径
export PATH="$HOME/flutter/bin:$PATH"

echo -e "${GREEN}🚀 MyData Flutter 编译安装脚本${NC}"
echo "=================================="

# 检查 Flutter 是否安装
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter 未安装或未添加到 PATH${NC}"
    echo "请确保 Flutter 已安装并添加到环境变量"
    exit 1
fi

# 检查设备连接
echo -e "${YELLOW}📱 检查 Android 设备连接...${NC}"
DEVICE_ID=$(adb devices | grep -v "List of devices" | grep "device$" | awk '{print $1}' | head -1)

if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}❌ 未检测到 Android 设备${NC}"
    echo "请确保："
    echo "1. 设备已通过 USB 连接"
    echo "2. 已启用 USB 调试"
    echo "3. 已授权此计算机"
    exit 1
fi

# 检查并卸载旧版本应用（如果存在）
echo -e "${YELLOW}🔍 检查旧版本应用...${NC}"
OLD_PACKAGES=$(adb shell pm list packages | grep -E "(com.example.mydata_flutter|tech.shupi.mydata)" | cut -d: -f2)
if [ -n "$OLD_PACKAGES" ]; then
    echo -e "${YELLOW}🗑️  发现旧版本，正在卸载...${NC}"
    echo "$OLD_PACKAGES" | while read -r package; do
        adb uninstall "$package" 2>/dev/null && echo "  ✓ 已卸载: $package" || echo "  ✗ 卸载失败: $package"
    done
fi

echo -e "${GREEN}✅ 检测到设备: $DEVICE_ID${NC}"

# 获取编译模式
BUILD_MODE=${1:-debug}

# 如果是 run 模式，直接运行
if [ "$BUILD_MODE" == "run" ]; then
    echo -e "\n${BLUE}🏃 运行 Flutter 应用（支持热重载）...${NC}"
    flutter run -d "$DEVICE_ID"
    exit 0
fi

# 验证编译模式
if [ "$BUILD_MODE" != "debug" ] && [ "$BUILD_MODE" != "release" ] && [ "$BUILD_MODE" != "profile" ]; then
    echo -e "${YELLOW}⚠️  无效的编译模式: $BUILD_MODE${NC}"
    echo "用法: $0 [debug|release|profile|run]"
    exit 1
fi

# 清理项目（可选，注释掉以加快编译速度）
# echo -e "\n${YELLOW}🧹 清理项目...${NC}"
# flutter clean

# 获取依赖
echo -e "\n${YELLOW}📦 获取依赖...${NC}"
flutter pub get

# 编译 APK
echo -e "\n${YELLOW}🔨 编译应用 ($BUILD_MODE 模式)...${NC}"

APK_PATH=""
if [ "$BUILD_MODE" == "release" ]; then
    echo -e "${YELLOW}⚠️  Release 模式需要签名配置${NC}"
    flutter build apk --release
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
elif [ "$BUILD_MODE" == "profile" ]; then
    flutter build apk --profile
    APK_PATH="build/app/outputs/flutter-apk/app-profile.apk"
else
    flutter build apk --debug
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
fi

# 安装 APK
if [ -f "$APK_PATH" ]; then
    echo -e "\n${YELLOW}📲 安装应用到设备...${NC}"
    adb install -r "$APK_PATH"
    
    # 启动应用
    echo -e "\n${YELLOW}🚀 启动应用...${NC}"
    adb shell am start -n tech.shupi.mydata/.MainActivity
    
    echo -e "\n${GREEN}✅ 完成！应用已安装并启动${NC}"
else
    echo -e "${RED}❌ APK 文件未找到: $APK_PATH${NC}"
    exit 1
fi

