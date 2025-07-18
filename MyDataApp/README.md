# MyData React Native App

这是 MyData 项目的 React Native 移动端应用，提供文件同步和管理的移动界面。

## 项目特性

- 📱 **React Native** - 跨平台移动应用开发
- 🎨 **React Native Paper** - Material Design 组件库
- 🔍 **可自定义搜索栏** - 支持高度、字体大小等自定义
- 📡 **API 集成** - 与 Syncthing 后端服务集成
- 🔄 **实时数据同步** - 支持下拉刷新和实时更新
- 🎯 **TypeScript** - 类型安全的开发体验

## 项目结构

```
MyDataApp/
├── src/
│   ├── components/          # 可复用组件
│   │   └── SearchBar.tsx    # 自定义搜索栏组件
│   ├── screens/             # 页面组件
│   │   └── HomeScreen.tsx   # 主屏幕
│   ├── services/            # API 服务
│   │   └── api.ts           # API 调用服务
│   ├── types/               # TypeScript 类型定义
│   │   └── index.ts         # 基本类型定义
│   └── utils/               # 工具函数
├── android/                 # Android 原生代码
├── ios/                     # iOS 原生代码
└── App.tsx                  # 主应用组件
```

## 主要组件

### SearchBar 组件
- 支持自定义高度、字体大小
- 内置清除按钮
- Material Design 风格
- 阴影和圆角效果

### HomeScreen 组件
- 设备列表显示
- 文件夹管理
- 搜索功能
- 下拉刷新
- 错误处理和提示

## 开发指南

### 环境要求
- Node.js >= 18
- React Native CLI
- Android Studio (Android 开发)
- Xcode (iOS 开发，仅 macOS)

### 安装依赖
```bash
npm install
```

### 运行应用

#### Android
```bash
# 启动 Metro 服务器
npm start

# 在另一个终端运行 Android 应用
npm run android
```

#### iOS (仅 macOS)
```bash
# 安装 iOS 依赖
cd ios && pod install && cd ..

# 启动 Metro 服务器
npm start

# 在另一个终端运行 iOS 应用
npm run ios
```

### 开发注意事项

1. **搜索栏自定义**
   - 使用 `height` 属性控制高度
   - 使用 `fontSize` 属性控制字体大小
   - 支持 `onClear` 回调函数

2. **API 集成**
   - 默认连接到 `localhost:8080`
   - 支持设备、文件夹管理
   - 统一的错误处理

3. **样式定制**
   - 使用 React Native Paper 主题
   - 支持自定义颜色和样式
   - Material Design 规范

## 与现有项目集成

这个 React Native 应用与现有的 MyData 项目集成：

- **API 兼容性**: 使用相同的 REST API 接口
- **数据格式**: 保持与桌面应用一致的数据结构
- **功能对应**: 提供相同的核心功能（设备管理、文件夹管理）

## 技术栈

- **React Native 0.80.1** - 移动应用框架
- **React Native Paper** - Material Design 组件
- **TypeScript** - 类型安全
- **React Native Vector Icons** - 图标库
- **React Native Safe Area Context** - 安全区域处理

## 贡献指南

1. 遵循 TypeScript 类型定义
2. 使用 React Native Paper 组件
3. 保持与桌面应用的一致性
4. 添加适当的错误处理
5. 测试跨平台兼容性
