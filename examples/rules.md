# 示例应用

源码在各 `*-app/` 目录。打包产物统一输出到 **`dist/`**（已 gitignore）。

```bash
cd examples
./pack.sh              # 打包全部
./pack.sh todo-app     # 只打某一个
```

生成：`dist/<app.id>-<version>.zip`，例如 `dist/todo-1.2.1.zip`。
