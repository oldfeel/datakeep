#!/bin/bash
# MyData Flutter Syncthing 库构建脚本
# 从 Go 版本移植而来

set -e

echo "🚀 MyData Flutter Syncthing 库构建工具"
echo "======================================"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录（mydata_flutter）
PROJECT_DIR="$SCRIPT_DIR"
# Syncthing 源代码目录
SYNCTHING_DIR="$(cd "$PROJECT_DIR/.." && pwd)/syncthing"

# 检查平台支持
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$PLATFORM" in
    linux)
        PLATFORM_DIR="linux-x86_64"
        ;;
    darwin)
        PLATFORM_DIR="darwin-x86_64"
        ;;
    *)
        echo "❌ 不支持的平台: $PLATFORM"
        echo "支持的平台: linux, darwin"
        exit 1
        ;;
esac

# 验证是否是 Flutter 项目
FLUTTER_PUBSPEC="$PROJECT_DIR/pubspec.yaml"
if [ ! -f "$FLUTTER_PUBSPEC" ]; then
    echo "❌ Flutter 项目未找到。期望 pubspec.yaml 位于: $FLUTTER_PUBSPEC"
    echo "   当前目录: $SCRIPT_DIR"
    echo "   项目目录: $PROJECT_DIR"
    exit 1
fi

echo "📁 Flutter 项目目录: $PROJECT_DIR"

# 检查 Syncthing 源代码是否存在
if [ ! -d "$SYNCTHING_DIR" ]; then
    echo "❌ Syncthing 源代码未找到: $SYNCTHING_DIR"
    echo "请将 syncthing 仓库克隆到父目录"
    exit 1
fi

# 获取最小 SDK 版本
get_min_sdk() {
    local gradle_file="$PROJECT_DIR/android/app/build.gradle.kts"
    if [ ! -f "$gradle_file" ]; then
        gradle_file="$PROJECT_DIR/android/app/build.gradle"
    fi
    
    if [ ! -f "$gradle_file" ]; then
        echo "⚠️  无法读取 build.gradle 文件，使用默认值 21" >&2
        echo 21
        return
    fi
    
    # 检查是否包含 flutter.minSdkVersion
    if grep -q "flutter.minSdkVersion" "$gradle_file"; then
        echo "📱 检测到 flutter.minSdkVersion，使用默认值 21" >&2
        echo 21
        return
    fi
    
    # 尝试提取 minSdk 值
    local min_sdk=$(grep -i "minSdk" "$gradle_file" | grep -oE '[0-9]+' | head -1)
    if [ -n "$min_sdk" ]; then
        echo "$min_sdk"
        return
    fi
    
    # 默认值
    echo 21
}

MIN_SDK=$(get_min_sdk)
echo "📱 Min SDK Version: $MIN_SDK"

# 获取 NDK 路径
get_ndk_home() {
    # 尝试从环境变量获取
    if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
        echo "$ANDROID_NDK_HOME"
        return
    fi
    
    # 尝试从 Android SDK 获取
    local android_home="$ANDROID_HOME"
    if [ -z "$android_home" ]; then
        android_home="$ANDROID_SDK_ROOT"
    fi
    
    if [ -n "$android_home" ]; then
        local ndk_version="$NDK_VERSION"
        
        # 如果没有指定版本，尝试查找最新版本
        if [ -z "$ndk_version" ]; then
            local ndk_dir="$android_home/ndk"
            if [ -d "$ndk_dir" ]; then
                # 查找最新的版本目录
                local latest_version=$(ls -1 "$ndk_dir" 2>/dev/null | sort -V | tail -1)
                if [ -n "$latest_version" ]; then
                    ndk_version="$latest_version"
                    echo "📦 自动检测到 NDK 版本: $ndk_version" >&2
                fi
            fi
            
            # 如果还是找不到，尝试默认版本列表
            if [ -z "$ndk_version" ]; then
                local versions=("27.1.12297006" "27.0.12077973" "23.1.7779620" "21.4.7075529")
                for v in "${versions[@]}"; do
                    local test_path="$android_home/ndk/$v"
                    if [ -d "$test_path" ]; then
                        ndk_version="$v"
                        echo "📦 使用默认 NDK 版本: $ndk_version" >&2
                        break
                    fi
                done
            fi
        fi
        
        if [ -n "$ndk_version" ]; then
            local ndk_home="$android_home/ndk/$ndk_version"
            if [ -d "$ndk_home" ]; then
                echo "$ndk_home"
                return
            fi
        fi
    fi
    
    # 系统默认路径
    if [ "$PLATFORM" = "linux" ]; then
        local default_paths=(
            "/home/oldfeel/Android/Sdk/ndk/27.1.12297006"
            "/home/oldfeel/Android/Sdk/ndk/27.0.12077973"
            "/home/oldfeel/Android/Sdk/ndk/23.1.7779620"
        )
        for path in "${default_paths[@]}"; do
            if [ -d "$path" ]; then
                echo "$path"
                return
            fi
        done
    fi
    
    echo ""
}

NDK_HOME=$(get_ndk_home)
if [ -z "$NDK_HOME" ]; then
    echo "❌ 未找到 NDK。请设置 ANDROID_NDK_HOME 或 ANDROID_HOME+NDK_VERSION"
    exit 1
fi
echo "🔧 NDK Home: $NDK_HOME"

# 构建目标架构
BUILD_TARGETS=(
    "arm:arm:armeabi-v7a:armv7a-linux-androideabi"
    "arm64:arm64:arm64-v8a:aarch64-linux-android"
    "x86:386:x86:i686-linux-android"
    "x86_64:amd64:x86_64:x86_64-linux-android"
)

# 创建构建目录
BUILD_DIR="$PROJECT_DIR/syncthing_build_cache"
GO_BUILD_DIR="$BUILD_DIR/go-packages"
mkdir -p "$BUILD_DIR"

# 为每个目标架构构建
for target in "${BUILD_TARGETS[@]}"; do
    IFS=':' read -r arch goarch jnidir cc_template <<< "$target"
    
    echo ""
    echo "🔨 Building syncthing for $arch ($jnidir)"
    
    # 构建 CC 路径
    CC="$NDK_HOME/toolchains/llvm/prebuilt/$PLATFORM_DIR/bin/${cc_template}${MIN_SDK}-clang"
    
    if [ ! -f "$CC" ]; then
        echo "⚠️  警告: CC 工具不存在: $CC"
        echo "   尝试查找替代路径..."
        # 尝试查找正确的 clang（按版本号查找）
        CC_CANDIDATE=$(find "$NDK_HOME/toolchains/llvm/prebuilt/$PLATFORM_DIR/bin" \
            -name "${cc_template}*-clang" 2>/dev/null | \
            grep -E "${cc_template}[0-9]+-clang$" | \
            sort -V | head -1)
        
        if [ -n "$CC_CANDIDATE" ] && [ -f "$CC_CANDIDATE" ]; then
            CC="$CC_CANDIDATE"
        else
            # 如果还是找不到，尝试查找任何匹配的 clang
            CC_CANDIDATE=$(find "$NDK_HOME/toolchains/llvm/prebuilt/$PLATFORM_DIR/bin" \
                -name "*${cc_template}*clang" 2>/dev/null | head -1)
            if [ -n "$CC_CANDIDATE" ] && [ -f "$CC_CANDIDATE" ]; then
                CC="$CC_CANDIDATE"
            else
                echo "❌ 无法找到 CC 工具"
                echo "   期望路径: $CC"
                echo "   请检查 NDK 安装或设置正确的 NDK 版本"
                exit 1
            fi
        fi
    fi
    
    echo "   使用 CC: $CC"
    echo "   目标架构: android/$goarch"
    
    # 执行构建
    # 参考官方 Python 脚本：https://github.com/syncthing/syncthing-android/blob/main/syncthing/build-syncthing.py
    # 只设置必要的环境变量，不设置 GOOS/GOARCH（让 build.go 通过参数设置）
    cd "$SYNCTHING_DIR"
    
    # 设置环境变量（类似 Python 的 os.environ.copy().update()）
    # 注意：不要设置 GOOS、GOARCH 和 CC 环境变量
    # build.go 会通过 -goos、-goarch 和 -cc 参数接收，并在 setBuildEnvVars() 中设置
    GO111MODULE=on \
    CGO_ENABLED=1 \
    SYNCTHING_ANDROID=1 \
    go run build.go \
        -goos android \
        -goarch "$goarch" \
        -cc "$CC" \
        -pkgdir "$GO_BUILD_DIR/$goarch" \
        -version "v1.28.1-mydata" \
        -no-upgrade \
        build
    
    # 检查编译结果
    if [ ! -f "$SYNCTHING_DIR/syncthing" ]; then
        echo "❌ 编译失败: 未找到 syncthing 可执行文件"
        exit 1
    fi
    
    # 复制编译结果到 jniLibs 目录
    TARGET_DIR="$PROJECT_DIR/android/app/src/main/jniLibs/$jnidir"
    mkdir -p "$TARGET_DIR"
    
    TARGET_ARTIFACT="$TARGET_DIR/libsyncthing.so"
    
    # 删除已存在的文件
    if [ -f "$TARGET_ARTIFACT" ]; then
        rm -f "$TARGET_ARTIFACT"
    fi
    
    # 复制编译结果
    cp "$SYNCTHING_DIR/syncthing" "$TARGET_ARTIFACT"
    chmod 755 "$TARGET_ARTIFACT"
    
    echo "✅ Successfully built and copied libsyncthing.so for $arch"
done

echo ""
echo "🎉 All builds completed successfully!"
echo "📁 Native libraries are available in: $PROJECT_DIR/android/app/src/main/jniLibs"

