# 生物（bio-app）

Vue 3 **无构建**示例：本地 SQLite 分类名录 + 虚拟列表 + 搜索上下文。

- `app.json` 声明 `"aiEditable": true`（可被 DataKeep 应用内 AI 改壳）
- 物种数据来自 SQLite，**不**靠 AI 生成全库

## 结构

| 路径 | 说明 |
|------|------|
| `index.html` / `app.js` / `app.css` | Vue 全局构建壳 |
| `vendor/` | `vue.global.prod.js`、sql.js |
| `seed/taxa.sqlite` | 联调样本库（数百节点） |
| `scripts/build_taxa_db.py` | 生成样本库；可选从 DwC-A 导入全库 |

## 浏览方式

右侧主面板有两种视图，用顶部「列表 / 导图」切换：

- **列表（默认）**：当前节点大标题 + 逐级下钻的卡片网格。每张卡片显示等级、中文名/学名和下级数量，
  点一下就进入下一级；面包屑与「↑ 上一级」可回退；选到「种」时下方列出同属其它种。
  子级按 `LIMIT/OFFSET` 分页（每页 160），超大节点不会一次拉全。
- **导图**：中心节点 + 祖先链 + 同级，适合看整体形态；单层超过 60 个子级会折叠成「还有 N 个…」。

左侧分类树始终可用（移动端为抽屉），行数很多时自动窗口化渲染。

## 本地生成样本库

```bash
python3 scripts/build_taxa_db.py
```

## 全库（开发机 / CI）

1. 取得 Catalogue of Life / GBIF Backbone 等开放名录的 DwC-A，解出 `Taxon.tsv`
2. 生成（体积可达约 0.5–2 GB+）：

```bash
python3 scripts/build_taxa_db.py --from-dwca /path/to/Taxon.tsv --out data/taxa.sqlite --version 2024.x
```

3. 将 `taxa.sqlite` 放到设备上应用目录的 `data/`（首次运行也可由壳下载；V1 样本为自动安装 `seed/` → `data/`）

许可须在应用内 / 本 README 标明（见 `DATA.md`）。

## 大数据量下的性能约定

- `taxa(parent_id)` / `taxa(parent_id, scientific_name)` 索引随库一起建好，`meta.index_rev` 记录版本
- 祖先链用**一条递归 CTE** 查询，不再逐层往返
- 左树窗口化（只渲染视口内约一屏行）、卡片列表分页、导图单层上限 60
- 计数优先读 `meta.species_count` / `meta.node_count`，避免频繁 `COUNT(*)`
- FTS 只在数据变化时 rebuild

## 打包

```bash
../pack.sh bio-app
```

静态包会打入 `seed/` 与 `vendor/`；`data/` 运行时生成，不进 zip。

## 行为摘要

- 主列表：仅 `rank=species`，按窗 `LIMIT/OFFSET` 查询，虚拟滚动
- 搜索：FTS / LIKE → 祖先链 + 同级种
- 首次打开：若无 `data/taxa.sqlite`，把样本写入 `data/`
