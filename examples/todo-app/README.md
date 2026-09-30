# 待办清单

符合 [应用包规范](../../docs/app-package-spec.md)。

**Vite + React + MUI** 待办应用（v2，不兼容 1.x 的 `todo.db` schema）。

## 功能

- **左栏**：自定义列表（新建 / 重命名 / 删除）
- **中栏**：添加任务；任务行显示标题、完成勾选、**创建时间**
- **右栏**：标题、步骤、截止日期、提醒、备注（Editor.js）、附件

## 数据

```text
data/
  todo.db                          # sql.js（lists / tasks / steps / attachments）
  attachments/<taskId>/<id>_文件   # 附件二进制
```

Syncthing 若产生 `todo.sync-conflict-*.db`，打开时按行 `id` + `updated_at` 合并后删除冲突副本。

**不要**对 `todo.db` 使用 `syncIgnore`。

## 开发

DataKeep **Debug** 下 AppRunner 会直连本仓库 `examples/todo-app/www/`（与 video-app 相同），数据仍用安装目录的 `data/`。

```bash
cd examples/todo-app
npm install
npm run build    # 首次 → www/
npm run dev      # vite build --watch，改代码约 2 秒热更新
```

```bash
cd examples && ./pack.sh todo-app
# => dist/site.datakeep.todo-2.0.0.zip
./publish.sh todo-app --bump patch   # 可选：升版本并上传市场
```
