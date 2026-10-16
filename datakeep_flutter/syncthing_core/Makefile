# DataKeep 共用 Syncthing 进程内引擎（gomobile）
# iOS → xcframework　Android → AAR　桌面暂用系统 syncthing，共用本目录 Go 源码思路
#
#   make android   # 产出 ../android/app/libs/syncthingcore.aar
#   make ios       # 产出 build/DataKeepSyncthing.xcframework（需 macOS）
#   make all       # 当前平台能构建的目标

PATH := $(HOME)/go/bin:/usr/local/go/bin:/opt/homebrew/bin:$(PATH)
SHELL := env PATH="$(PATH)" /bin/bash

IOS_VERSION ?= 13.0
ANDROID_API ?= 24
OUT_IOS := build/DataKeepSyncthing.xcframework
OUT_AAR := ../android/app/libs/syncthingcore.aar

# 自动探测 NDK
ANDROID_HOME ?= $(HOME)/Android/Sdk
NDK_CANDIDATE := $(firstword $(wildcard $(ANDROID_HOME)/ndk/*))
ANDROID_NDK_HOME ?= $(NDK_CANDIDATE)

.PHONY: all deps fix-gui-assets android ios clean test help

help:
	@echo "make android  - gomobile bind → $(OUT_AAR)"
	@echo "make ios      - gomobile bind → $(OUT_IOS)（需 Xcode）"
	@echo "make deps     - 安装 gomobile"
	@echo "国内网络: export GOPROXY=https://goproxy.cn,direct"

all: android

deps:
	go install golang.org/x/mobile/cmd/gomobile@latest
	go install golang.org/x/mobile/cmd/gobind@latest
	gomobile init

# gui.files.go 为生成文件；缺 !noassets 时与 noassets.go 的 Assets 冲突（-tags noassets）
fix-gui-assets:
	@bash "$(CURDIR)/fix_gui_assets.sh"

$(OUT_AAR): *.go go.mod Makefile | fix-gui-assets
	@if [ -z "$(ANDROID_NDK_HOME)" ] || [ ! -d "$(ANDROID_NDK_HOME)" ]; then \
		echo "未找到 Android NDK。请设置 ANDROID_NDK_HOME 或安装到 \$$ANDROID_HOME/ndk/"; \
		exit 1; \
	fi
	@mkdir -p $(dir $(OUT_AAR))
	cd $(CURDIR) && go mod tidy
	ANDROID_NDK_HOME="$(ANDROID_NDK_HOME)" ANDROID_HOME="$(ANDROID_HOME)" \
	gomobile bind \
		-target android \
		-androidapi $(ANDROID_API) \
		-tags noassets \
		-ldflags '-checklinkname=0' \
		-o $(OUT_AAR) \
		.
	@echo "✓ 已生成 $(OUT_AAR)"

android: deps $(OUT_AAR)

# replace 链入 ../../syncthing；子模块关键文件变更也需重建
ST_DEPS := ../../syncthing/lib/connections/service.go \
	../../syncthing/lib/connections/relay_listen.go \
	../../syncthing/lib/relay/client/dynamic.go

$(OUT_IOS): *.go go.mod Makefile $(ST_DEPS) | fix-gui-assets
	@mkdir -p build
	gomobile bind \
		-target ios,iossimulator \
		-iosversion=$(IOS_VERSION) \
		-tags noassets \
		-o $(OUT_IOS) \
		.
	@echo "✓ 已生成 $(OUT_IOS)"

ios: deps $(OUT_IOS)

# 兼容旧目标名
build: ios

clean:
	rm -rf build $(OUT_AAR)

test:
	go test -tags noassets ./...
