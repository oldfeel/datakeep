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
	// 直接使用 NDK 路径
	ndkHome := "C:/Users/hyt59/AppData/Local/Android/Sdk/ndk/29.0.13113456"
	if _, err := os.Stat(ndkHome); err != nil {
		return "", fmt.Errorf("NDK path not found: %v", err)
	}
	return ndkHome, nil
}

func getMinSDK(projectDir string) (int, error) {
	gradleFile := filepath.Join(projectDir, "app", "build.gradle.kts")
	content, err := os.ReadFile(gradleFile)
	if err != nil {
		return 0, fmt.Errorf("failed to read build.gradle.kts: %v", err)
	}

	lines := strings.Split(string(content), "\n")
	for _, line := range lines {
		tokens := strings.Fields(line)
		if len(tokens) == 3 && tokens[0] == "minSdk" {
			var sdk int
			if _, err := fmt.Sscanf(tokens[2], "%d", &sdk); err != nil {
				return 0, fmt.Errorf("failed to parse minSdk: %v", err)
			}
			return sdk, nil
		}
	}

	return 0, fmt.Errorf("failed to find minSdkVersion")
}

func main() {
	// 获取当前目录
	moduleDir, err := os.Getwd()
	if err != nil {
		fmt.Printf("Error getting current directory: %v\n", err)
		os.Exit(1)
	}

	// 检查平台支持
	platform := runtime.GOOS
	if _, ok := platformDirs[platform]; !ok {
		fmt.Printf("Unsupported platform %s. Supported platforms: %s\n",
			platform, strings.Join(getKeys(platformDirs), ", "))
		os.Exit(1)
	}

	// 获取项目根目录
	projectDir := filepath.Dir(moduleDir)

	// 获取构建目录
	buildDir := filepath.Join(moduleDir, "gobuild")
	goBuildDir := filepath.Join(buildDir, "go-packages")
	syncthingDir := filepath.Join(moduleDir, "..", "..", "syncthing")

	// 获取最小 SDK 版本
	minSDK, err := getMinSDK(projectDir)
	if err != nil {
		fmt.Printf("Error getting min SDK: %v\n", err)
		os.Exit(1)
	}

	// 获取 NDK 路径
	ndkHome, err := getNDKHome()
	if err != nil {
		fmt.Printf("Error getting NDK home: %v\n", err)
		os.Exit(1)
	}

	// 为每个目标架构构建
	for _, target := range buildTargets {
		fmt.Printf("Building syncthing for %s\n", target.Arch)

		// 设置环境变量
		env := append(os.Environ(),
			"GO111MODULE=on",
			"CGO_ENABLED=1",
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
			"-no-upgrade", "build")
		cmd.Dir = syncthingDir
		cmd.Env = env
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			fmt.Printf("Error building for %s: %v\n", target.Arch, err)
			os.Exit(1)
		}

		// 复制编译结果到 jniLibs 目录
		targetDir := filepath.Join(projectDir, "app", "src", "main", "jniLibs", target.JniDir)
		if err := os.MkdirAll(targetDir, 0755); err != nil {
			fmt.Printf("Error creating target directory: %v\n", err)
			os.Exit(1)
		}

		targetArtifact := filepath.Join(targetDir, "libsyncthing.so")
		if err := os.RemoveAll(targetArtifact); err != nil {
			fmt.Printf("Error removing existing artifact: %v\n", err)
			os.Exit(1)
		}

		if err := os.Rename(
			filepath.Join(syncthingDir, "syncthing"),
			targetArtifact,
		); err != nil {
			fmt.Printf("Error moving artifact: %v\n", err)
			os.Exit(1)
		}

		fmt.Printf("Finished build for %s\n", target.Arch)
	}

	fmt.Println("All builds finished")
}

func getKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}
