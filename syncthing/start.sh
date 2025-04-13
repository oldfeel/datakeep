#!/bin/bash

# 构建项目
echo "正在构建项目..."
./build.sh

# 启动 syncthing
echo "正在启动 syncthing..."
go run ./cmd/syncthing/ -no-upgrade