# MyData iOS Syncthing 进程内引擎（gomobile → xcframework）
# 用法：make  或  make build

PATH := $(HOME)/go/bin:/opt/homebrew/bin:$(PATH)
SHELL := env PATH="$(PATH)" /bin/bash

IOS_VERSION ?= 13.0
OUT := build/MyDataSyncthing.xcframework

.PHONY: all build deps clean test

all: build

deps:
	go install golang.org/x/mobile/cmd/gomobile@latest
	go install golang.org/x/mobile/cmd/gobind@latest
	gomobile init

$(OUT): *.go go.mod Makefile
	@mkdir -p build
	gomobile bind \
		-target ios,iossimulator \
		-iosversion=$(IOS_VERSION) \
		-tags noassets \
		-o $(OUT) \
		.
	@echo "✓ 已生成 $(OUT)"

build: deps $(OUT)

clean:
	rm -rf build

test:
	go test -tags noassets ./...
