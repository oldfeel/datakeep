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
			JniDir: "armeabi-v7a",
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
			ndkVersion = "29.0.13113456" // 默认版本
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

func getMinSDK(projectDir string) (int, error) {
	// 尝试读取 build.gradle.kts 文件
	gradleFile := filepath.Join(projectDir, "android", "app", "build.gradle.kts")
	content, err := os.ReadFile(gradleFile)
	if err != nil {
		// 如果 build.gradle.kts 不存在，尝试读取 build.gradle
		gradleFile = filepath.Join(projectDir, "android", "app", "build.gradle")
		content, err = os.ReadFile(gradleFile)
		if err != nil {
			return 0, fmt.Errorf("failed to read build.gradle files: %v", err)
		}
	}

	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		// 处理 build.gradle.kts 格式
		if strings.Contains(line, "minSdk") {
			// 提取数字
			for _, token := range strings.Fields(line) {
				if strings.HasSuffix(token, ",") || strings.HasSuffix(token, ")") {
					token = strings.TrimRight(token, ",)")
				}
				var sdk int
				if _, err := fmt.Sscanf(token, "%d", &sdk); err == nil && sdk > 0 {
					return sdk, nil
				}
			}
		}
	}

	// 如果找不到，返回默认值
	return 24, nil
}

func main() {
	fmt.Println("🚀 MyDataApp Syncthing 库构建工具")
	fmt.Println("==================================")

	// 获取当前目录
	moduleDir, err := os.Getwd()
	if err != nil {
		fmt.Printf("❌ Error getting current directory: %v\n", err)
		os.Exit(1)
	}

	// 检查平台支持
	platform := runtime.GOOS
	if _, ok := platformDirs[platform]; !ok {
		fmt.Printf("❌ Unsupported platform %s. Supported platforms: %s\n",
			platform, strings.Join(getKeys(platformDirs), ", "))
		os.Exit(1)
	}

	// 获取项目根目录
	projectDir := filepath.Dir(moduleDir)

	// 获取构建目录
	buildDir := filepath.Join(moduleDir, "gobuild")
	goBuildDir := filepath.Join(buildDir, "go-packages")
	syncthingDir := filepath.Join(projectDir, "..", "syncthing")

	// 检查 Syncthing 源代码是否存在
	if _, err := os.Stat(syncthingDir); os.IsNotExist(err) {
		fmt.Printf("❌ Syncthing source code not found at: %s\n", syncthingDir)
		fmt.Println("Please clone syncthing repository to the parent directory")
		os.Exit(1)
	}

	// 获取最小 SDK 版本
	minSDK, err := getMinSDK(projectDir)
	if err != nil {
		fmt.Printf("❌ Error getting min SDK: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("📱 Min SDK Version: %d\n", minSDK)

	// 获取 NDK 路径
	ndkHome, err := getNDKHome()
	if err != nil {
		fmt.Printf("❌ Error getting NDK home: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("🔧 NDK Home: %s\n", ndkHome)

	// 创建构建目录
	if err := os.MkdirAll(buildDir, 0755); err != nil {
		fmt.Printf("❌ Error creating build directory: %v\n", err)
		os.Exit(1)
	}

	// 为每个目标架构构建
	for _, target := range buildTargets {
		fmt.Printf("\n🔨 Building syncthing for %s (%s)\n", target.Arch, target.JniDir)

		// 设置环境变量
		env := append(os.Environ(),
			"GO111MODULE=on",
			"CGO_ENABLED=1",
			"SYNCTHING_ANDROID=1",
		)

		// 构建命令
		cc := filepath.Join(ndkHome, "toolchains", "llvm", "prebuilt",
			platformDirs[platform], "bin",
			fmt.Sprintf(target.CC, minSDK))

		// 执行构建
		cmd := exec.Command("go", "run", "build.go",
			"-goos", "android",
			"-goarch", target.GoArch,
			"-cc", cc,
			"-pkgdir", filepath.Join(goBuildDir, target.GoArch),
			"-version", "v1.28.1-mydata",
			"-no-upgrade", "build")
		cmd.Dir = syncthingDir
		cmd.Env = env
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			fmt.Printf("❌ Error building for %s: %v\n", target.Arch, err)
			os.Exit(1)
		}

		// 复制编译结果到 jniLibs 目录
		targetDir := filepath.Join(projectDir, "android", "app", "src", "main", "jniLibs", target.JniDir)
		if err := os.MkdirAll(targetDir, 0755); err != nil {
			fmt.Printf("❌ Error creating target directory: %v\n", err)
			os.Exit(1)
		}

		targetArtifact := filepath.Join(targetDir, "libsyncthing.so")
		if err := os.RemoveAll(targetArtifact); err != nil {
			fmt.Printf("❌ Error removing existing artifact: %v\n", err)
			os.Exit(1)
		}

		if err := os.Rename(
			filepath.Join(syncthingDir, "syncthing"),
			targetArtifact,
		); err != nil {
			fmt.Printf("❌ Error moving artifact: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("✅ Successfully built for %s\n", target.Arch)
	}

	fmt.Println("\n🎉 All builds completed successfully!")
	fmt.Printf("📁 Native libraries are available in: %s\n",
		filepath.Join(projectDir, "android", "app", "src", "main", "jniLibs"))
}

func getKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}
