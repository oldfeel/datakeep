package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

type BuildTarget struct {
	Arch   string
	GoArch string
	JniDir string
	CC     string
}

var PLATFORM_DIRS = map[string]string{
	"windows": "windows-x86_64",
	"linux":   "linux-x86_64",
	"darwin":  "darwin-x86_64",
}

var BUILD_TARGETS = []BuildTarget{
	{"arm", "arm", "armeabi", "armv7a-linux-androideabi%d-clang"},
	{"arm64", "arm64", "arm64-v8a", "aarch64-linux-android%d-clang"},
	{"x86", "386", "x86", "i686-linux-android%d-clang"},
	{"x86_64", "amd64", "x86_64", "x86_64-linux-android%d-clang"},
}

func fail(message string, args ...interface{}) {
	fmt.Printf(message+"\n", args...)
	os.Exit(1)
}

func getMinSdk(projectDir string) int {
	gradleFile := filepath.Join(projectDir, "app", "build.gradle.kts")
	data, err := os.ReadFile(gradleFile)
	if err != nil {
		fail("Failed to read build.gradle.kts: %v", err)
	}
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "minSdk") {
			var minSdk int
			fmt.Sscanf(line, "minSdk = %d", &minSdk)
			return minSdk
		}
	}
	fail("Failed to find minSdkVersion")
	return -1
}

func getNDKHome() string {
	ndkHome := os.Getenv("ANDROID_NDK_HOME")
	ndkVersion := os.Getenv("NDK_VERSION")
	androidHome := os.Getenv("ANDROID_HOME")

	if ndkHome == "" {
		if ndkVersion == "" || androidHome == "" {
			fail("ANDROID_NDK_HOME or NDK_VERSION and ANDROID_HOME must be defined")
		}
		return filepath.Join(androidHome, "ndk", ndkVersion)
	}
	return ndkHome
}

func main() {
	platform, exists := PLATFORM_DIRS[runtime.GOOS]
	if !exists {
		fail("Unsupported platform %s. Supported platforms: %v", runtime.GOOS, PLATFORM_DIRS)
	}

	moduleDir, _ := os.Getwd()
	projectDir := filepath.Join(moduleDir, "..")
	buildDir := filepath.Join(moduleDir, "gobuild")
	goBuildDir := filepath.Join(buildDir, "go-packages")
	syncthingDir := filepath.Join(moduleDir, "../../syncthing")
	minSdk := getMinSdk(projectDir)
	fmt.Printf("minSdk: %d\n", minSdk)
	ndkHome := getNDKHome()

	for _, target := range BUILD_TARGETS {
		fmt.Println("Building syncthing for", target.Arch)
		cc := filepath.Join(ndkHome, "toolchains", "llvm", "prebuilt", platform, "bin", fmt.Sprintf(target.CC, minSdk))

		cmds := [][]string{
			{"go", "version"},
			{"go", "run", "build.go", "version"},
			{"go", "run", "build.go", "-goos", "android", "-goarch", target.GoArch, "-cc", cc, "-pkgdir", filepath.Join(goBuildDir, target.GoArch), "-no-upgrade", "build"},
		}

		for _, cmdArgs := range cmds {
			fmt.Println(strings.Join(cmdArgs, " "))
			cmd := exec.Command(cmdArgs[0], cmdArgs[1:]...)
			cmd.Env = append(os.Environ(), "GO111MODULE=on", "CGO_ENABLED=1")
			cmd.Dir = syncthingDir
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			if err := cmd.Run(); err != nil {
				fail("Command failed: %v", err)
			}
		}

		targetDir := filepath.Join(projectDir, "app", "src", "main", "jniLibs", target.JniDir)
		os.MkdirAll(targetDir, os.ModePerm)
		targetArtifact := filepath.Join(targetDir, "libsyncthing.so")
		os.Remove(targetArtifact)
		os.Rename(filepath.Join(syncthingDir, "syncthing"), targetArtifact)

		fmt.Println("Finished build for", target.Arch)
	}

	fmt.Println("All builds finished")
}
