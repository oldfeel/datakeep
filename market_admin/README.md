# MyData 应用市场管理后台

基于 [material-ui-vite-ts](https://github.com/mui/material-ui/tree/master/examples/material-ui-vite-ts) 思路：Vite + React + TS + MUI。

```bash
cd market_admin
npm install
npm run dev
```

开发时 Vite 将 `/admin`、`/api` 代理到 `http://127.0.0.1:8088`。

生产构建：

```bash
npm run build
# 将 dist/ 部署到 Nginx，反代 API 到 market_server
```

环境变量 `VITE_API_BASE`：直连 API 时填写，如 `http://192.168.2.10:8088`（开发走代理可留空）。
