# DataKeep 应用包规范

应用是可同步的特殊文件夹（客户端 `kind=app`），以 zip 分发，由应用市场安装。

## 包结构

zip 解压后根目录（或唯一顶层目录）须包含：

| 路径 | 必填 | 说明 |
|------|------|------|
| `app.json` | 是 | 应用清单 |
| `index.html` | 是 | 默认入口（可被 `app.json` 的 `entry` 覆盖） |
| `data/` | 否 | 用户数据目录；**更新时保留**，安装器不得覆盖已有 `data/` |
| 其他 css/js/图片等 | 否 | 相对路径引用即可 |

## app.json

```json
{
  "id": "hello",
  "name": "Hello DataKeep",
  "version": "1.0.0",
  "entry": "index.html",
  "description": "示例应用",
  "icon": "icon.png"
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `id` | 是 | 稳定标识，小写字母/数字/连字符；本地文件夹 id 为 `app-{id}` |
| `name` | 是 | 显示名 |
| `version` | 是 | semver，如 `1.0.0` |
| `entry` | 否 | 入口 HTML，默认 `index.html` |
| `description` | 否 | 简介 |
| `icon` | 否 | 包内相对路径图标 |
| `syncIgnore` | 否 | 字符串数组，安装/打开时合并进应用目录 `.stignore`（及独立同步文件夹的忽略规则）。常用：`["*.db"]` 忽略本机 SQLite 缓存 |

## 校验

- 市场上架时：包内必须存在有效 `app.json` 与入口 HTML。
- 分发文件附带 **sha256**，客户端安装前校验。

## 安装约定（客户端）

- 解压到：应用文档目录下 `DataKeepApps/<app.id>/`
- Syncthing 文件夹 id：`app-<app.id>`
- 标记 `kind=app`
- 更新：覆盖非 `data/` 文件；保留已有 `data/`
- 卸载：删除同步文件夹与本地目录（可按产品确认是否删磁盘）
- 若存在 `syncIgnore`：写入 `.stignore`，并对已注册的同步文件夹调用忽略规则 API 合并

## 运行时数据 API（客户端 AppRunner）

内嵌打开应用时，本机 HTTP 除静态文件外提供：

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/__datakeep/data/<相对路径>` | 读文件；若路径为目录则返回 `{"files":["相对 data/ 的路径",...]}` |
| PUT | `/__datakeep/data/<相对路径>` | 写入（自动创建目录）；禁止 `..` |
| DELETE | `/__datakeep/data/<相对路径>` | 删除文件 |
| GET | `/__datakeep/revision` | `{"dataRev":ms,"appRev":ms}`：`data/` 与其余应用文件的最大修改时间，用于自动刷新 |

打开应用时客户端会轮询 revision：`appRev` 变化则重载 WebView；`dataRev` 变化则向页面派发 `datakeep:data-changed`（示例应用会据此重新读库）。

## 运行环境

- 应用在 DataKeep 内嵌 WebView 中打开（本机 HTTP + `/__datakeep/data/`）。
- 使用 sql.js（`vendor/sql-wasm.js`）时，脚本需兼容较旧的 Android System WebView（建议 Chrome/WebView ≥ 85；仓库示例已对 `||=` / `?.` 等语法做降级）。
- 若提示「未加载 sql-wasm.js」，先确认 `vendor/` 已同步完整，再尝试升级「Android System WebView」或 Chrome。

### 多设备数据建议

| 场景 | 做法 |
|------|------|
| 数据量大、单表 | 同步单个 `*.db`；表内用稳定 `id` + `updatedAt`；打开时合并 `*.sync-conflict-*.db`（见 `examples/todo-app`） |
| 记录多、常并发改不同行 | 也可用「一记录一文件」；小文件多时列表/IO 可能更慢 |

**不要**对正在作为同步源的 `*.db` 使用 `syncIgnore`：忽略后对端收不到库，无法合并。

`syncIgnore` 仍可用于真正只需本机的缓存文件（若与同步源分离）。

## 示例

仓库 `examples/`：`hello-app`、`ledger-app`（记账）、`todo-app`（待办）。
