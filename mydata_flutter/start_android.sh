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

# 第一步：编译生成可执行文件
echo -e "\n${BLUE}📦 第一步：编译生成可执行文件${NC}"
echo "=============================="

# 确保使用正确的 Go 版本
export PATH=/usr/local/go/bin:$PATH

# 1.1 检查并编译 Android 版本的 Backend (AAR)
echo -e "\n${YELLOW}1.1 检查 Android 版本的 Backend (AAR)...${NC}"
AAR_FILE="$SCRIPT_DIR/android/app/libs/backend.aar"

if [ ! -f "$AAR_FILE" ]; then
    echo -e "${YELLOW}AAR 未编译，开始编译...${NC}"
    
    # 进入 backend 目录
    cd "$SCRIPT_DIR/backend"
    
    # 检查 gomobile 是否已安装
    if ! command -v gomobile &> /dev/null; then
        echo -e "${YELLOW}gomobile 未安装，正在安装...${NC}"
        go install golang.org/x/mobile/cmd/gomobile@latest
        gomobile init
    fi
    
    # 确保依赖已下载
    echo -e "${BLUE}📦 下载依赖...${NC}"
    go mod download
    
    # 从 Go 1.16 开始，建议在执行 gomobile bind 前先执行 go get
    echo -e "${BLUE}📦 确保 mobile 依赖已添加...${NC}"
    go get -d golang.org/x/mobile/cmd/gomobile
    
    # 创建输出目录
    OUTPUT_DIR="../android/app/libs"
    mkdir -p "$OUTPUT_DIR"
    
    # 构建 AAR
    echo -e "${BLUE}🔨 开始构建 AAR...${NC}"
    # 设置使用本地 toolchain，避免下载问题
    export GOTOOLCHAIN=local
    gomobile bind -v \
        -target=android \
        -androidapi=19 \
        -o "$OUTPUT_DIR/backend.aar" \
        ./mobile
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ AAR 构建成功！${NC}"
        echo -e "${GREEN}📦 输出文件: $OUTPUT_DIR/backend.aar${NC}"
    else
        echo -e "${RED}❌ AAR 构建失败${NC}"
        cd "$SCRIPT_DIR"
        exit 1
    fi
    
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ AAR 编译完成${NC}"
else
    echo -e "${GREEN}✅ AAR 已编译: $AAR_FILE${NC}"
fi

# 1.2 检查并编译 Android 版本的 Syncthing
echo -e "\n${YELLOW}1.2 检查 Android 版本的 Syncthing...${NC}"
JNILIBS_DIR="$SCRIPT_DIR/android/app/src/main/jniLibs"
NEED_BUILD_SYNCTHING=false

# 检查是否所有架构的 .so 文件都存在
ARCHS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")
for arch in "${ARCHS[@]}"; do
    SO_FILE="$JNILIBS_DIR/$arch/libsyncthing.so"
    if [ ! -f "$SO_FILE" ]; then
        NEED_BUILD_SYNCTHING=true
        break
    fi
done

if [ "$NEED_BUILD_SYNCTHING" = true ]; then
    echo -e "${YELLOW}Syncthing 未编译或文件不完整，开始编译...${NC}"
    
    # Syncthing 源代码目录
    SYNCTHING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/syncthing"
    
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
            echo -e "${RED}❌ 不支持的平台: $PLATFORM${NC}"
            echo "支持的平台: linux, darwin"
            exit 1
            ;;
    esac
    
    # 检查 Syncthing 源代码是否存在
    if [ ! -d "$SYNCTHING_DIR" ]; then
        echo -e "${RED}❌ Syncthing 源代码未找到: $SYNCTHING_DIR${NC}"
        echo "请将 syncthing 仓库克隆到父目录"
        exit 1
    fi
    
    # 获取最小 SDK 版本
    get_min_sdk() {
        local gradle_file="$SCRIPT_DIR/android/app/build.gradle.kts"
        if [ ! -f "$gradle_file" ]; then
            gradle_file="$SCRIPT_DIR/android/app/build.gradle"
        fi
        
        if [ ! -f "$gradle_file" ]; then
            echo 21
            return
        fi
        
        # 检查是否包含 flutter.minSdkVersion
        if grep -q "flutter.minSdkVersion" "$gradle_file"; then
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
    echo -e "${BLUE}📱 Min SDK Version: $MIN_SDK${NC}"
    
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
                    local latest_version=$(ls -1 "$ndk_dir" 2>/dev/null | sort -V | tail -1)
                    if [ -n "$latest_version" ]; then
                        ndk_version="$latest_version"
                    fi
                fi
                
                # 如果还是找不到，尝试默认版本列表
                if [ -z "$ndk_version" ]; then
                    local versions=("27.1.12297006" "27.0.12077973" "23.1.7779620" "21.4.7075529")
                    for v in "${versions[@]}"; do
                        local test_path="$android_home/ndk/$v"
                        if [ -d "$test_path" ]; then
                            ndk_version="$v"
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
        echo -e "${RED}❌ 未找到 NDK。请设置 ANDROID_NDK_HOME 或 ANDROID_HOME+NDK_VERSION${NC}"
        exit 1
    fi
    echo -e "${BLUE}🔧 NDK Home: $NDK_HOME${NC}"
    
    # 构建目标架构
    BUILD_TARGETS=(
        "arm:arm:armeabi-v7a:armv7a-linux-androideabi"
        "arm64:arm64:arm64-v8a:aarch64-linux-android"
        "x86:386:x86:i686-linux-android"
        "x86_64:amd64:x86_64:x86_64-linux-android"
    )
    
    # 创建构建目录
    BUILD_DIR="$SCRIPT_DIR/syncthing_build_cache"
    GO_BUILD_DIR="$BUILD_DIR/go-packages"
    mkdir -p "$BUILD_DIR"
    
    # 为每个目标架构构建
    for target in "${BUILD_TARGETS[@]}"; do
        IFS=':' read -r arch goarch jnidir cc_template <<< "$target"
        
        echo ""
        echo -e "${BLUE}🔨 Building syncthing for $arch ($jnidir)${NC}"
        
        # 构建 CC 路径
        CC="$NDK_HOME/toolchains/llvm/prebuilt/$PLATFORM_DIR/bin/${cc_template}${MIN_SDK}-clang"
        
        if [ ! -f "$CC" ]; then
            echo -e "${YELLOW}⚠️  警告: CC 工具不存在: $CC${NC}"
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
                    echo -e "${RED}❌ 无法找到 CC 工具${NC}"
                    echo "   期望路径: $CC"
                    echo "   请检查 NDK 安装或设置正确的 NDK 版本"
                    exit 1
                fi
            fi
        fi
        
        echo "   使用 CC: $CC"
        echo "   目标架构: android/$goarch"
        
        # 执行构建
        cd "$SYNCTHING_DIR"
        
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
            echo -e "${RED}❌ 编译失败: 未找到 syncthing 可执行文件${NC}"
            cd "$SCRIPT_DIR"
            exit 1
        fi
        
        # 复制编译结果到 jniLibs 目录
        TARGET_DIR="$SCRIPT_DIR/android/app/src/main/jniLibs/$jnidir"
        mkdir -p "$TARGET_DIR"
        
        TARGET_ARTIFACT="$TARGET_DIR/libsyncthing.so"
        
        # 删除已存在的文件
        if [ -f "$TARGET_ARTIFACT" ]; then
            rm -f "$TARGET_ARTIFACT"
        fi
        
        # 复制编译结果
        cp "$SYNCTHING_DIR/syncthing" "$TARGET_ARTIFACT"
        chmod 755 "$TARGET_ARTIFACT"
        
        echo -e "${GREEN}✅ Successfully built and copied libsyncthing.so for $arch${NC}"
    done
    
    cd "$SCRIPT_DIR"
    echo ""
    echo -e "${GREEN}🎉 All Syncthing builds completed successfully!${NC}"
    echo -e "${GREEN}📁 Native libraries are available in: $JNILIBS_DIR${NC}"
    echo -e "${GREEN}✅ Syncthing 编译完成${NC}"
else
    echo -e "${GREEN}✅ Syncthing 已编译（所有架构的 .so 文件都存在）${NC}"
fi

echo -e "${GREEN}✅ 可执行文件准备完成${NC}"

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

