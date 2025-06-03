#!/bin/bash
# 启动 syncthing，不检查新版本

go run ./cmd/syncthing/ -no-upgrade "$@"
