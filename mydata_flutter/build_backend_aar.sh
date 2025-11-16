#!/bin/bash

# 构建 backend 为 Android AAR 的脚本

set -e

echo "=== 开始构建 backend AAR ==="

# 确保使用正确的 Go 版本（优先使用 /usr/local/go/bin）
export PATH=/usr/local/go/bin:$PATH

# 进入 backend 目录
cd "$(dirname "$0")/backend"

# 检查 gomobile 是否已安装
if ! command -v gomobile &> /dev/null; then
    echo "❌ gomobile 未安装，正在安装..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    gomobile init
fi

# 确保依赖已下载
echo "📦 下载依赖..."
go mod download

# 从 Go 1.16 开始，建议在执行 gomobile bind 前先执行 go get
echo "📦 确保 mobile 依赖已添加..."
go get -d golang.org/x/mobile/cmd/gomobile

# 创建输出目录
OUTPUT_DIR="../android/app/libs"
mkdir -p "$OUTPUT_DIR"

# 构建 AAR
echo "🔨 开始构建 AAR..."
# 设置使用本地 toolchain，避免下载问题
export GOTOOLCHAIN=local
gomobile bind -v \
    -target=android \
    -androidapi=19 \
    -o "$OUTPUT_DIR/backend.aar" \
    ./mobile

if [ $? -eq 0 ]; then
    echo "✅ AAR 构建成功！"
    echo "📦 输出文件: $OUTPUT_DIR/backend.aar"
    echo ""
    echo "下一步："
    echo "1. 在 Android Studio 中打开项目"
    echo "2. 在 android/app/build.gradle.kts 中添加依赖"
    echo "3. 重新构建项目"
else
    echo "❌ AAR 构建失败"
    exit 1
fi

