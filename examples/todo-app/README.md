# 待办清单（todo）

符合 [应用包规范](../../docs/app-package-spec.md)。

## 数据与冲突

数据只存在 **`data/todo.db`**（单文件，适合数据量大），由 Syncthing 同步该文件。

**不要**对 `todo.db` 使用 `syncIgnore`：忽略后设备之间传不过去，也就无法合并。

两边几乎同时改时，Syncthing 可能留下：

```text
todo.db
todo.sync-conflict-YYYYMMDD-HHMMSS-XXXXX.db
```

打开应用（或回到前台、或检测到 `data/` 变更）时会：

1. 读主库 + 所有冲突副本
2. 按任务 **`id`（UUID）** 对齐，取 **`updated_at` 较新** 的一侧（删除为软删 `deleted=1`）
3. 写回 `todo.db`，删除冲突副本

应用代码更新后，DataKeep AppRunner 会自动重载 WebView；数据文件变更约 2 秒内自动读盘刷新。

须在 DataKeep 客户端内打开。

## 打包

```bash
cd examples && ./pack.sh todo-app
# => dist/todo-1.2.1.zip
```

上架：管理后台「应用」上传 zip。
