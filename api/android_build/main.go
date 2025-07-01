package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

var (
	platformDirs = map[string]string{
		"windows": "windows-x86_64",
		"linux":   "linux-x86_64",
		"darwin":  "darwin-x86_64",
	}

	buildTargets = []struct {
		Arch   string
		GoArch string
		JniDir string
		CC     string
	}{
		{
			Arch:   "arm",
			GoArch: "arm",
			JniDir: "armeabi",
			CC:     "armv7a-linux-androideabi%d-clang",
		},
		{
			Arch:   "arm64",
			GoArch: "arm64",
			JniDir: "arm64-v8a",
			CC:     "aarch64-linux-android%d-clang",
		},
		{
			Arch:   "x86",
			GoArch: "386",
			JniDir: "x86",
			CC:     "i686-linux-android%d-clang",
		},
		{
			Arch:   "x86_64",
			GoArch: "amd64",
			JniDir: "x86_64",
			CC:     "x86_64-linux-android%d-clang",
		},
	}
)

func getNDKHome() (string, error) {
	// 尝试从环境变量获取 NDK 路径
	ndkHome := os.Getenv("ANDROID_NDK_HOME")
	if ndkHome != "" {
		if _, err := os.Stat(ndkHome); err == nil {
			return ndkHome, nil
		}
	}

	// 尝试从 Android SDK 获取 NDK 路径
	androidHome := os.Getenv("ANDROID_HOME")
	if androidHome != "" {
		ndkVersion := os.Getenv("NDK_VERSION")
		if ndkVersion == "" {
			ndkVersion = "25.1.8937393" // 默认版本
		}
		ndkHome = filepath.Join(androidHome, "ndk", ndkVersion)
		if _, err := os.Stat(ndkHome); err == nil {
			return ndkHome, nil
		}
	}

	// 系统默认路径
	if runtime.GOOS == "windows" {
		defaultPath := "C:/Users/hyt59/AppData/Local/Android/Sdk/ndk/29.0.13113456"
		if _, err := os.Stat(defaultPath); err == nil {
			return defaultPath, nil
		}
	} else if runtime.GOOS == "linux" {
		defaultPath := "/home/oldfeel/Android/Sdk/ndk/29.0.13113456"
		if _, err := os.Stat(defaultPath); err == nil {
			return defaultPath, nil
		}
	}

	return "", fmt.Errorf("NDK not found. Please set ANDROID_NDK_HOME or ANDROID_HOME+NDK_VERSION")
}

func buildWithNDK() error {
	fmt.Println("=== 使用 NDK 构建 Android 版本 ===")

	// 获取当前目录
	moduleDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("error getting current directory: %v", err)
	}

	// 检查平台支持
	platform := runtime.GOOS
	if _, ok := platformDirs[platform]; !ok {
		return fmt.Errorf("unsupported platform %s. Supported platforms: %s",
			platform, strings.Join(getKeys(platformDirs), ", "))
	}

	// 获取项目根目录
	projectDir := filepath.Dir(moduleDir)   // android_build -> api
	apiDir := projectDir                    // api 目录
	projectRoot := filepath.Dir(projectDir) // api -> mydata

	// 检查 API 目录是否存在
	if _, err := os.Stat(apiDir); err != nil {
		return fmt.Errorf("API directory not found: %s", apiDir)
	}

	// 获取 NDK 路径
	ndkHome, err := getNDKHome()
	if err != nil {
		return fmt.Errorf("error getting NDK home: %v", err)
	}

	fmt.Printf("使用 NDK: %s\n", ndkHome)

	// 设置最小 SDK 版本
	minSDK := 21 // Android 5.0

	// 为每个目标架构构建
	for _, target := range buildTargets {
		fmt.Printf("构建 MyData API for %s\n", target.Arch)

		// 设置环境变量
		env := append(os.Environ(),
			"GO111MODULE=on",
			"CGO_ENABLED=1",
			"GOOS=android",
			"GOARCH="+target.GoArch,
		)

		// 构建命令
		cc := filepath.Join(ndkHome, "toolchains", "llvm", "prebuilt",
			platformDirs[platform], "bin",
			fmt.Sprintf(target.CC, minSDK))

		// 设置 CGO 编译器
		env = append(env, "CC="+cc)

		// 执行构建 - 使用构建标签 android
		cmd := exec.Command("go", "build", "-tags=android", "-o", "mydata-api", ".")
		cmd.Dir = apiDir
		cmd.Env = env
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			return fmt.Errorf("error building for %s: %v", target.Arch, err)
		}

		// 创建输出目录
		outputDir := filepath.Join(projectRoot, "syncthing-android", "app", "src", "main", "jniLibs", target.JniDir)
		if err := os.MkdirAll(outputDir, 0755); err != nil {
			return fmt.Errorf("error creating output directory: %v", err)
		}

		// 复制编译结果
		targetArtifact := filepath.Join(outputDir, "libmydata-api.so")
		if err := os.RemoveAll(targetArtifact); err != nil {
			return fmt.Errorf("error removing existing artifact: %v", err)
		}

		if err := os.Rename(
			filepath.Join(apiDir, "mydata-api"),
			targetArtifact,
		); err != nil {
			return fmt.Errorf("error moving artifact: %v", err)
		}

		fmt.Printf("Finished build for %s: %s\n", target.Arch, targetArtifact)
	}

	fmt.Println("=== 所有构建完成 ===")
	return nil
}

func main() {
	fmt.Println("=== MyData API Android 构建工具 ===")

	fmt.Println("使用 NDK 构建...")
	if err := buildWithNDK(); err != nil {
		fmt.Printf("NDK 构建失败: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("=== 构建成功完成 ===")
	fmt.Println("输出目录: ../syncthing-android/app/src/main/jniLibs/")
	fmt.Println("")
	fmt.Println("下一步:")
	fmt.Println("1. 在 syncthing-android 项目中添加 MyDataApiService 服务")
	fmt.Println("2. 在 AndroidManifest.xml 中注册服务")
	fmt.Println("3. 编译并安装 syncthing-android 应用")
}

func getKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}
