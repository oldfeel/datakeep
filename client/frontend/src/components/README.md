# 组件说明

## 组件结构

### 主要组件

#### DeviceInfoCard
- **位置**: `src/components/DeviceInfoCard.tsx`
- **功能**: 显示设备基本信息，支持设备名称编辑、设备ID复制、移除设备
- **Props**:
  - `device`: 设备信息
  - `onDeviceNameChange`: 设备名称变更回调
  - `onRemoveDevice`: 移除设备回调

#### FolderList
- **位置**: `src/components/FolderList.tsx`
- **功能**: 显示文件夹列表，支持添加、编辑、删除文件夹
- **Props**:
  - `folders`: 文件夹列表
  - `deviceName`: 设备名称
  - `deviceId`: 设备ID
  - `onRefresh`: 刷新回调

#### FolderEditDialog
- **位置**: `src/components/FolderEditDialog.tsx`
- **功能**: 文件夹编辑对话框，支持基本设置、共享设置、忽略模式、高级设置
- **Props**:
  - `open`: 是否打开
  - `folder`: 要编辑的文件夹
  - `onClose`: 关闭回调
  - `onSave`: 保存回调
  - `onDelete`: 删除回调
  - `isAddMode`: 是否为添加模式

### 工具函数

#### folderUtils
- **位置**: `src/utils/folderUtils.ts`
- **功能**: 文件夹相关的工具函数
- **函数**:
  - `generateFolderId()`: 生成随机文件夹ID

### 类型定义

#### types
- **位置**: `src/types/index.ts`
- **功能**: 共享的类型定义
- **接口**:
  - `Folder`: 文件夹接口
  - `Device`: 设备接口

## 使用说明

1. 所有组件都使用 TypeScript 进行类型检查
2. 组件遵循 Material-UI 设计规范
3. 错误处理通过 Snackbar 显示
4. 支持中文界面和提示信息
5. 组件间通过 props 和回调函数进行通信

## 开发规范

1. 使用函数式组件和 React Hooks
2. 遵循单一职责原则
3. 保持组件的可复用性
4. 使用 TypeScript 接口确保类型安全
5. 实现适当的错误处理和加载状态 