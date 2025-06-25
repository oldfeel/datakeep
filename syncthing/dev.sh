#!/bin/bash
# 启动 syncthing，不检查新版本

# 杀死已有的 syncthing 进程
echo "正在检查并杀死已有的 Syncthing 进程..."
pkill -f syncthing 2>/dev/null || true

# 等待进程完全退出
sleep 1

# 清理可能的数据库锁定文件
echo "清理数据库锁定文件..."
rm -f ~/.local/state/syncthing/index-v0.14.0.db/LOCK 2>/dev/null || true
rm -f ~/.config/syncthing/index-v0.14.0.db/LOCK 2>/dev/null || true

echo "启动 Syncthing..."
go run ./cmd/syncthing/ -no-upgrade "$@"
