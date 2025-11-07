package main

import (
	"fmt"
	"io"
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
	if androidHome == "" {
		androidHome = os.Getenv("ANDROID_SDK_ROOT")
	}

	if androidHome != "" {
		ndkVersion := os.Getenv("NDK_VERSION")
		if ndkVersion == "" {
			// 尝试查找最新的 NDK 版本
			ndkDir := filepath.Join(androidHome, "ndk")
			if entries, err := os.ReadDir(ndkDir); err == nil {
				// 查找最新的版本（按名称排序）
				var latestVersion string
				for _, entry := range entries {
					if entry.IsDir() {
						version := entry.Name()
						if latestVersion == "" || version > latestVersion {
							latestVersion = version
						}
					}
				}
				if latestVersion != "" {
					ndkVersion = latestVersion
					fmt.Printf("📦 自动检测到 NDK 版本: %s\n", ndkVersion)
				}
			}

			// 如果还是找不到，使用默认版本列表（从新到旧）
			if ndkVersion == "" {
				versions := []string{"27.1.12297006", "27.0.12077973", "23.1.7779620", "21.4.7075529"}
				for _, v := range versions {
					testPath := filepath.Join(androidHome, "ndk", v)
					if _, err := os.Stat(testPath); err == nil {
						ndkVersion = v
						fmt.Printf("📦 使用默认 NDK 版本: %s\n", ndkVersion)
						break
					}
				}
			}
		}

		if ndkVersion != "" {
			ndkHome = filepath.Join(androidHome, "ndk", ndkVersion)
			if _, err := os.Stat(ndkHome); err == nil {
				return ndkHome, nil
			}
		}
	}

	// 系统默认路径
	if runtime.GOOS == "linux" {
		defaultPaths := []string{
			"/home/oldfeel/Android/Sdk/ndk/27.1.12297006",
			"/home/oldfeel/Android/Sdk/ndk/27.0.12077973",
			"/home/oldfeel/Android/Sdk/ndk/23.1.7779620",
		}
		for _, defaultPath := range defaultPaths {
			if _, err := os.Stat(defaultPath); err == nil {
				return defaultPath, nil
			}
		}
	} else if runtime.GOOS == "windows" {
		defaultPath := "C:/Users/hyt59/AppData/Local/Android/Sdk/ndk/29.0.13846066"
		if _, err := os.Stat(defaultPath); err == nil {
			return defaultPath, nil
		}
	}

	return "", fmt.Errorf("NDK not found. Please set ANDROID_NDK_HOME or ANDROID_HOME+NDK_VERSION")
}

func getMinSDK(projectDir string) (int, error) {
	// Flutter 项目使用 flutter.minSdkVersion，需要从 local.properties 或 gradle.properties 读取
	// 或者尝试读取 build.gradle.kts 文件
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
		// 处理 build.gradle.kts 格式：minSdk = flutter.minSdkVersion
		// Flutter 默认 minSdkVersion 通常是 21
		if strings.Contains(line, "minSdk") {
			// 检查是否是 flutter.minSdkVersion
			if strings.Contains(line, "flutter.minSdkVersion") {
				// Flutter 默认值是 21，但可以通过 local.properties 覆盖
				// 这里返回 Flutter 的默认值
				return 21, nil
			}
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

	// Flutter 默认 minSdk 是 21
	return 21, nil
}

func main() {
	fmt.Println("🚀 MyData Flutter Syncthing 库构建工具")
	fmt.Println("======================================")

	// 获取当前目录（syncthing_build 目录）
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

	// 获取项目根目录（mydata_flutter）
	// syncthing_build 目录在项目根目录下，所以上一级目录就是项目根目录
	projectDir := filepath.Dir(moduleDir)

	// 验证是否是 Flutter 项目
	flutterPubspec := filepath.Join(projectDir, "pubspec.yaml")
	if _, err := os.Stat(flutterPubspec); os.IsNotExist(err) {
		fmt.Printf("❌ Flutter project not found. Expected pubspec.yaml at: %s\n", flutterPubspec)
		fmt.Printf("   Current directory: %s\n", moduleDir)
		fmt.Printf("   Project directory: %s\n", projectDir)
		os.Exit(1)
	}

	fmt.Printf("📁 Flutter 项目目录: %s\n", projectDir)

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

		// 删除已存在的文件
		if _, err := os.Stat(targetArtifact); err == nil {
			if err := os.Remove(targetArtifact); err != nil {
				fmt.Printf("⚠️  Warning: Failed to remove existing artifact: %v\n", err)
			}
		}

		// 复制编译结果
		sourceArtifact := filepath.Join(syncthingDir, "syncthing")
		if _, err := os.Stat(sourceArtifact); os.IsNotExist(err) {
			fmt.Printf("❌ Source artifact not found: %s\n", sourceArtifact)
			os.Exit(1)
		}

		// 使用 CopyFile 而不是 Rename，因为可能跨文件系统
		if err := copyFile(sourceArtifact, targetArtifact); err != nil {
			fmt.Printf("❌ Error copying artifact: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("✅ Successfully built and copied libsyncthing.so for %s\n", target.Arch)
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

// copyFile 复制文件
func copyFile(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer sourceFile.Close()

	destFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer destFile.Close()

	_, err = io.Copy(destFile, sourceFile)
	if err != nil {
		return err
	}

	// 设置文件权限
	return os.Chmod(dst, 0755)
}
