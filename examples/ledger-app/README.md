# 简单记账

符合 [应用包规范](../../docs/app-package-spec.md)。使用 **sql.js**，库文件落在 `data/ledger.db`（经 DataKeep AppRunner 的 `/__datakeep/data/` 读写，可随同步文件夹跨设备）。

须在 DataKeep 客户端内打开本应用；直接用文件协议打开无法落盘。数据文件变更时会自动刷新。

## 打包

```bash
cd examples && ./pack.sh ledger-app
# => dist/site.datakeep.ledger-1.0.4.zip
```

上架：管理后台「应用」上传 zip。
