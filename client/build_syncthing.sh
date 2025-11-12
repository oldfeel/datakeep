#!/bin/bash
# 编译 Syncthing 可执行文件

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SYNCTHING_DIR="$PROJECT_ROOT/syncthing"
BIN_DIR="$SYNCTHING_DIR/bin"

echo "📦 开始编译 Syncthing..."
echo "   项目根目录: $PROJECT_ROOT"
echo "   Syncthing 目录: $SYNCTHING_DIR"

# 检查 syncthing 目录是否存在
if [ ! -d "$SYNCTHING_DIR" ]; then
    echo "❌ 错误: Syncthing 目录不存在: $SYNCTHING_DIR"
    exit 1
fi

# 进入 syncthing 目录
cd "$SYNCTHING_DIR"

# 检查 build.go 是否存在
if [ ! -f "build.go" ]; then
    echo "❌ 错误: build.go 不存在"
    exit 1
fi

# 创建 bin 目录
mkdir -p "$BIN_DIR"

# 编译 Syncthing
echo "🔨 正在编译 Syncthing..."
# 使用 -version 参数指定版本号，格式必须符合 Syncthing 的要求
# 格式: v<major>.<minor>.<patch>[-<suffix>]
go run build.go -version "v1.28.1-mydata" -no-upgrade build syncthing

# 检查编译结果
if [ -f "syncthing" ]; then
    # 移动到 bin 目录
    mv syncthing "$BIN_DIR/syncthing"
    chmod +x "$BIN_DIR/syncthing"
    echo "✅ Syncthing 编译成功: $BIN_DIR/syncthing"
    
    # 显示文件信息
    ls -lh "$BIN_DIR/syncthing"
else
    echo "❌ 编译失败: 未找到 syncthing 可执行文件"
    exit 1
fi

