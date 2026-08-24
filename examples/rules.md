# 内置 / 示例应用编写规则

正式协议见 [应用包规范](../docs/app-package-spec.md)。本文约束 `examples/*-app` 的实现约定（可作第三方应用参考）。

## 目录与打包

| 路径 | 说明 |
|------|------|
| `examples/<id>-app/` | 源码（如 `todo-app`） |
| `examples/dist/` | 打包产物（gitignore，勿提交） |
| `app.json` + 入口 HTML | 必填 |
| `data/` | 用户数据；**安装/更新不得覆盖**已有内容；打包时排除 |

```bash
cd examples
./pack.sh              # 全部 → dist/<id>-<version>.zip
./pack.sh todo-app     # 单个
```

- `app.json` 的 `id` / `version` 决定 zip 文件名。
- 改 `id` 或逻辑/数据协议后务必升 `version` 再打包上架；`id` 变更视为新应用，需在市场新建条目。

## app.json

```json
{
  "id": "site.datakeep.todo",
  "name": "待办清单",
  "version": "1.2.3",
  "entry": "index.html",
  "description": "…",
  "syncIgnore": []
}
```

- `id`：稳定包名（至少两段，如 `site.datakeep.todo`）；文件夹 id 为 `app-<id>`。
- `syncIgnore`：可选。**仅**对本机缓存、且**不是**跨设备同步源的文件使用（见下节）。

## 运行环境

- 必须在 DataKeep 客户端 AppRunner 内打开（本机 HTTP），不要依赖 `file://`。
- 静态资源相对路径引用；不要写死绝对盘符。
- UI / 注释用中文。

### 宿主 API（`/__datakeep/…`）

| 用途 | 接口 |
|------|------|
| 读写用户数据 | `GET/PUT/DELETE /__datakeep/data/<相对路径>`；目录 `GET` 返回 `{"files":[…]}` |
| 感知变更 | `GET /__datakeep/revision` → `{ dataRev, appRev }`（毫秒 mtime） |

推荐封装（见 `todo-app/db.js` / `ledger-app/db.js`）：

- `DataKeepDb.open` / `persist` / `schedulePersist`
- `DataKeepDb.watchData(onChange)`：轮询 revision + 监听 `datakeep:data-changed`
- 本机 `PUT` 后调用 `ackDataRevision()`，避免刚写入又被自动刷新冲掉

宿主行为：

- `appRev` 变 → WebView / 页面重载（代码热更新）
- `dataRev` 变 → 派发 `datakeep:data-changed`；应用应重新读盘并刷新 UI

## 数据库与多设备同步（重点）

Syncthing 同步的是**文件**，不懂表行。应用必须自己处理「行级」语义。

### 推荐：单库文件 + 冲突合并（数据量大）

适用于 todo / ledger 等（参考 `todo-app`）：

1. **权威数据**放在 `data/<name>.db`（如 `todo.db`），由 Syncthing 同步该文件。
2. **不要**对同步源 `*.db` 配置 `syncIgnore`。忽略后对端收不到库，无法合并。
3. 表结构约定：
   - 主键 `id`：稳定唯一（推荐 UUID 字符串，禁止依赖两端各自的自增整数当跨设备 id）
   - `updated_at`（ISO8601）：每次修改刷新
   - 删除用软删 `deleted=1`（并更新 `updated_at`），便于传播到对端
4. 并发写入时 Syncthing 可能产生：
   ```text
   todo.db
   todo.sync-conflict-YYYYMMDD-HHMMSS-XXXXX.db
   ```
5. **打开时 / `data-changed` / 回到前台** 必须：
   - 读主库 + 所有对应冲突副本
   - 按 `id` 对齐，取 `updated_at` 较新的一侧（相同时可约定软删优先）
   - 写回主库，删除冲突副本
6. 内存中的 sql.js 与磁盘不同步：变更后 `schedulePersist`；收到外部变更后重新 `open` 再合并。

### 备选：一记录一文件

记录少、常改不同行时可用 `data/items/<id>.json`。小文件极多时列表与 IO 更慢；本仓库内置示例优先单库方案。

### `syncIgnore` 何时用

| 可以忽略 | 不可以忽略 |
|----------|------------|
| 纯本机缓存、且另有同步源 | 正在作为跨设备同步源的 `*.db` |
| 例如派生索引、临时文件 | 唯一的 `todo.db` / `ledger.db` |

## 实现检查清单

- [ ] `app.json` id/version/name 正确；打包进 `dist/`
- [ ] 用户数据只写 `data/`；更新应用不丢 `data/`
- [ ] 跨设备主键为 UUID（或等价稳定 id）+ `updated_at`
- [ ] 删除为软删（若需多设备一致）
- [ ] 启动与 `watchData` 时合并 `*.sync-conflict-*.db`
- [ ] 未对同步源 db 使用 `syncIgnore`
- [ ] 使用 `/__datakeep/data` 落盘；接入 `watchData` 自动刷新

## 现有示例

| 目录 | 说明 |
|------|------|
| `hello-app` | 入门示例：最小包结构 |
| `todo-app` | 待办清单：SQLite + 冲突合并 + 自动刷新（范本） |
| `ledger-app` | 简单记账：SQLite 记账 + 自动刷新 |
