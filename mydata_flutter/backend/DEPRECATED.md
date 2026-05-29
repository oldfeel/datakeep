# DEPRECATED — Go 后端（已停维）

此目录包含 Go（Fiber + GORM）实现的后端代码，**已停止维护**。

## 迁移

Go backend 的所有功能已用纯 Dart（shelf）重写，位于 `lib/core/backend/`。

| 旧文件 | Dart 替代 |
|---|---|
| `backend/main.go` | `lib/core/backend/backend_server.dart` |
| `backend/handlers.go` | 合并到 `backend_server.dart` |
| `backend/core.go` | `lib/core/backend/syncthing_api.dart` |
| `backend/syncthing_manager.go` | `lib/core/services/native_service.dart`（已有） |
| `backend/cert_manager.go` | `lib/core/backend/cert_manager.dart` |

## 保留原因

Dart backend 在 Android 端依赖 `Process.start` 启动 Syncthing。如果该方案有兼容问题，可参考此目录的 Go 实现。
