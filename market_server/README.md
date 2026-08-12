# DataKeep 应用市场 API

Go Fiber + GORM + Postgres。管理端 JWT；公开 `/api/apps*`；zip 直传七牛/S3（本服务签发凭证）。

**不使用 Docker**，本机 Postgres + `go run` / 编译二进制即可。详见 [docs/market-deploy.md](../docs/market-deploy.md)。

## 运行

先建库与专用账号（不要用超级用户 `postgres` 跑应用）：

```bash
export PGPASSWORD='postgres超级用户密码'
psql -h 127.0.0.1 -U postgres <<'SQL'
CREATE ROLE datakeep_market LOGIN PASSWORD '应用专用密码';
CREATE DATABASE datakeep_market OWNER datakeep_market;
GRANT ALL PRIVILEGES ON DATABASE datakeep_market TO datakeep_market;
\c datakeep_market
GRANT ALL ON SCHEMA public TO datakeep_market;
ALTER SCHEMA public OWNER TO datakeep_market;
SQL
```

配置：复制 `.env.example` 为 `.env`，`DATABASE_URL` 使用 `user=datakeep_market`。然后：

```bash
cd market_server
go run .
```

默认监听见 `.env` 的 `ADDR`（如 `0.0.0.0:8088`）。局域网主机示例：`192.168.2.10`。

## 主要接口

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/admin/login` | 登录，返回 token |
| GET | `/admin/apps` | 应用列表（需 JWT） |
| POST | `/admin/apps` | 创建应用 |
| POST | `/admin/uploads/token` | 直传凭证 `{appId,version}` |
| POST | `/admin/apps/:id/versions` | 登记版本（设为当前） |
| GET | `/api/apps` | 公开列表（仅有当前版本的） |
| GET | `/api/apps/:appKey` | 详情 |
| GET | `/api/apps/:appKey/download` | 下载元信息 |
| GET | `/api/apps/:appKey/package` | 代下 zip（私有桶） |
