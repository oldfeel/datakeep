# 应用市场部署（局域网 192.168.2.10）

不用 Docker。本机安装 Postgres，直接跑 Go 与静态前端。

## 组件

- 系统 Postgres + `market_server`（`:8088`）
- `market_admin`（开发用 Vite；生产用 Nginx 静态或 `npm run preview`）
- Flutter 默认市场 API：`http://192.168.2.10:8088`

## 1. Postgres

```bash
sudo -u postgres createdb datakeep_market
# 按需设置用户密码，写入下方 DATABASE_URL
```

## 2. 启动 API

```bash
cd market_server
export ADDR=0.0.0.0:8088
export DATABASE_URL="host=127.0.0.1 user=postgres password=postgres dbname=datakeep_market port=5432 sslmode=disable"
export JWT_SECRET=change-me
export ADMIN_USERNAME=admin
export ADMIN_PASSWORD=admin123
# 七牛或 S3（管理员市场桶，与用户分享配置无关）
export QINIU_ACCESS_KEY=...
export QINIU_SECRET_KEY=...
export QINIU_BUCKET=...
export QINIU_DOMAIN=https://...

go run .
# 或：go build -o market_server . && ./market_server
```

可用 systemd 保活，工作目录指向 `market_server`，Environment 写入上述变量。

## 3. 管理后台

```bash
cd market_admin
npm install
npm run dev            # 开发，代理到本机 :8088
# 生产：
npm run build          # 产出 dist/
```

生产可用 Nginx：静态托管 `market_admin/dist`，并把 `/api`、`/admin` 反代到 `127.0.0.1:8088`。
