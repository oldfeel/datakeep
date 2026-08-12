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

## 校验

- 市场上架时：包内必须存在有效 `app.json` 与入口 HTML。
- 分发文件附带 **sha256**，客户端安装前校验。

## 安装约定（客户端）

- 解压到：应用文档目录下 `DataKeepApps/<app.id>/`
- Syncthing 文件夹 id：`app-<app.id>`
- 标记 `kind=app`
- 更新：覆盖非 `data/` 文件；保留已有 `data/`
- 卸载：删除同步文件夹与本地目录（可按产品确认是否删磁盘）
