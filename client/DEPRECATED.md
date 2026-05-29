# DEPRECATED — Wails 桌面应用（已停维）

此目录包含 Wails 桌面应用代码，**已停止维护**。

| 目录 | 状态 |
|---|---|
| `client/` | 已停维 |
| `client/frontend/` | React/TS 前端，已停维 |
| `client/app.go` | Wails Go 绑定，已停维 |
| `client/backend/` | 后端 API 原始版，**保留参考**（`mydata_flutter/backend/` 的母版） |

## 迁移目标

所有功能已迁移到 `mydata_flutter/`（Flutter 跨平台应用）。

## 保留原因

`client/backend/` 中的 Go 代码是 `mydata_flutter/backend/` 的母版，修改后端逻辑时仍可参考。

**修改 Go 后端时请直接改 `mydata_flutter/backend/`，不再需要同步 `client/backend/`。**
