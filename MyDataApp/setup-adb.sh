#!/bin/bash

# MyDataApp ADB 端口转发设置脚本

echo "🔧 设置 ADB 端口转发..."

# 检查设备连接
echo "📱 检查设备连接..."
adb devices

# 设置端口转发
echo "🔄 设置端口转发..."
adb reverse tcp:8081 tcp:8081  # Metro bundler
adb reverse tcp:8082 tcp:8082  # 备用端口
adb reverse tcp:8083 tcp:8083  # 备用端口

# 验证端口转发
echo "✅ 验证端口转发设置..."
adb reverse --list

echo "🎉 ADB 端口转发设置完成！"
echo ""
echo "现在你可以："
echo "1. 运行 'npm start' 启动 Metro bundler"
echo "2. 在设备上摇动设备或按菜单键打开开发者菜单"
echo "3. 选择 'Settings' -> 'Debug server host & port for device'"
echo "4. 输入 'localhost:8081'"
echo "5. 重新加载应用" 