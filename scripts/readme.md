# scripts 脚本说明

仓库根目录 `scripts/` 下的常用脚本。发版相关以 **`release.sh`** 为主（子命令合一，不必记多个文件名）。

---

## 客户端发版流程（推荐）

是的，日常发版大致就是这四步，**按顺序**执行：

```bash
cd scripts   # 或在仓库根目录用 ./scripts/release.sh

# 1. 发版：改版本号 → 打 tag → 推送 → 等 GitHub Actions 编完
./release.sh

# 2. 同步官网：服务器从 GitHub Release 拉包、写下载链、生成 .torrent
./release.sh market

# 3. 本机下载：四端安装包 + 官网 .torrent → dist-release/vX.Y.Z/
./release.sh download

# 4. 本机做种：Transmission 添加种子，数据目录指向 packages/
./release.sh seed
```

### 各步依赖关系

| 步骤 | 做什么 | 前置条件 |
|------|--------|----------|
| `release` | 触发 CI「Build packages」，产物挂到 [GitHub Release](https://github.com/oldfeel/datakeep/releases) | 工作区干净；需 `git`、`gh`（跟踪 CI 时） |
| `market` | 调用官网 `sync-github`，生成 BT 种子与磁力链 | **上一步 CI 已成功**；需市场管理员账号 |
| `download` | 从 GitHub 拉四端包，从官网拉 `.torrent` | Release 已有资产；**最好先 `market`**（否则没有 .torrent） |
| `seed` | 用 Transmission RPC 添加做种 | **先 `download`**；Transmission 已开「远程控制」 |

说明：

- 第 1 步结束后，若本机已配置市场账号，脚本会**自动尝试**官网同步；失败或未配置时，再单独跑第 2 步 `./release.sh market`。
- 不想等 CI 时可：`./release.sh --no-wait`，到 Actions 页确认编完后再执行 `market` → `download` → `seed`。
- 指定版本示例：`./release.sh market v0.1.1`、`./release.sh download v0.1.1`、`./release.sh seed v0.1.1`。

---

## release.sh

发版与分发的一站式脚本（在 `scripts/` 下执行 `./release.sh`，或仓库根 `./scripts/release.sh`）。

### 发版（默认）

```bash
./release.sh              # 版本末位 +1（十进制进位：0.0.9 → 0.1.0）
./release.sh 1.2.0        # 设为指定版本
./release.sh patch|minor|major
./release.sh --dry-run      # 只预览
./release.sh --no-wait      # 推送后不等待 CI
./release.sh --skip-market  # 不同步官网
./release.sh --proxy        # gh / 下载走本机代理（或 DATAKEEP_USE_PROXY=1）
```

### 官网与市场

```bash
./release.sh market           # 同步最新 tag 到官网（别名：sync、qiniu）
./release.sh market v0.1.1    # 指定 tag
./release.sh links            # 打印 GitHub Release 四端直链
./release.sh torrents         # 打印官网四端磁力链（需先 market）
```

**市场账号**（三选一）：

- 旁路仓库 `../datakeep-market/market_server/.env` 的 `ADMIN_USERNAME` / `ADMIN_PASSWORD`
- 或 `DATAKEEP_MARKET_TOKEN`
- 或 `DATAKEEP_MARKET_USER` + `DATAKEEP_MARKET_PASSWORD`

可选：`DATAKEEP_MARKET_URL`（默认 `https://admin.datakeep.site`）。

### 本机下载与做种

```bash
./release.sh download              # 默认最新 tag → dist-release/
./release.sh download v0.1.1
./release.sh download v0.1.1 --torrents-only   # 只补 .torrent
./release.sh download v0.1.1 --skip-pgyer      # 不上传 APK 到蒲公英

./release.sh seed                  # Transmission 做种（默认最新 tag）
./release.sh seed v0.1.1
./release.sh seed v0.1.1 --remove-old          # 移除旧版 datakeep-* 种子
./release.sh seed v0.1.1 --dry-run
```

**download 产物布局：**

```
dist-release/v0.1.1/
├── packages/          # 四端安装包（做种数据目录）
├── torrents/          # android / linux / macos / windows .torrent
└── magnets.txt        # 磁力链汇总
```

**Transmission 做种：**

- macOS：Transmission → 设置 → 远程 → 勾选「允许远程访问」（默认 `localhost:9091`）
- 若设 RPC 密码：`export TRANSMISSION_AUTH='用户:密码'` 再 `seed`
- 未安装 `transmission-remote` 时，脚本会用 curl 调 HTTP RPC

**蒲公英（可选）：** `download` 完成后可自动上传 Android APK；配置 `PGYER_API_KEY` 或旁路 `.env`，或 `--skip-pgyer` 跳过。

---

## build.sh

**本机**编译安装包（不推 tag、不走 CI），产物在仓库根 `dist/`。

```bash
./scripts/build.sh              # 当前系统能编的目标
./scripts/build.sh android linux
./scripts/build.sh --help
```

也可在发版脚本里：`./release.sh --local`（仅本机 `./scripts/build.sh`，不打远程 tag）。

桌面端需先编译 Syncthing：`bash scripts/build_desktop_syncthing.sh`（在仓库根执行）。

---

## start_avd.sh

启动 Android 模拟器。

```bash
./scripts/start_avd.sh <AVD名称>
./scripts/start_avd.sh          # 默认 Pixel_Tablet
```

---

## 相关文档

- 仓库根 [AGENTS.md](../AGENTS.md)：开发与架构约定
- GitHub Actions：`.github/workflows/build.yml`（push `v*` tag 自动编四端）
- 应用市场服务端：私有仓 [datakeep-market](https://github.com/oldfeel/datakeep-market)
