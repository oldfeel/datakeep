#!/bin/bash

# MyDataApp Syncthing 构建脚本

set -e  # 遇到错误时退出

echo "🚀 MyDataApp Syncthing 构建脚本"
echo "================================"

# 检查 Go 是否安装
if ! command -v go &> /dev/null; then
    echo "❌ Go 未安装，请先安装 Go 1.21+"
    exit 1
fi

# 检查 Go 版本
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo "📦 Go 版本: $GO_VERSION"

# 检查 Android NDK
if [ -z "$ANDROID_NDK_HOME" ] && [ -z "$ANDROID_HOME" ]; then
    echo "❌ 未设置 Android NDK 环境变量"
    echo "请设置以下环境变量之一："
    echo "  export ANDROID_NDK_HOME=/path/to/ndk"
    echo "  或者"
    echo "  export ANDROID_HOME=/path/to/sdk"
    echo "  export NDK_VERSION=29.0.13113456"
    exit 1
fi

# 检查 Syncthing 源代码
SYNCTHING_DIR="../syncthing"
if [ ! -d "$SYNCTHING_DIR" ]; then
    echo "❌ Syncthing 源代码未找到: $SYNCTHING_DIR"
    echo "请克隆 Syncthing 源代码："
    echo "  cd .."
    echo "  git clone https://github.com/syncthing/syncthing.git"
    exit 1
fi

echo "✅ Syncthing 源代码已找到: $SYNCTHING_DIR"

# 进入构建目录
cd lib_build

# 下载依赖
echo "📥 下载 Go 依赖..."
go mod download

# 运行构建
echo "🔨 开始构建 Syncthing..."
go run main.go

echo ""
echo "🎉 构建完成！"
echo "📁 库文件位置: android/app/src/main/jniLibs/"
echo ""
echo "下一步："
echo "1. 构建 Android 应用: npm run android"
echo "2. 或者在 Android Studio 中打开 android/ 目录" 