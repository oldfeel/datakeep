# 名录数据与许可

## 样本库（`seed/taxa.sqlite`）

- **来源**：手写代表性分类树，仅供 UI / 虚拟列表 / 搜索联调
- **许可**：示例数据视为 **CC0**（可自由使用）
- **体量**：数百节点，非地球全部物种

## 全库目标（可选）

目标量级约为 Catalogue of Life / GBIF Backbone 等开放名录的**全部有效种名**（约数百万种）。

| 步骤 | 说明 |
|------|------|
| 下载 | 官方 DwC-A 或等价导出（开发机 / CI，非手机 npm） |
| 清洗 | `scripts/build_taxa_db.py --from-dwca Taxon.tsv` |
| 分发 | **不要**打进小安装包；首次运行下载到 `data/taxa.sqlite`，或经 DataKeep 同步旁路数据文件夹 |
| 版本 | `meta.version` + 可选 `data/taxa.meta.json` |

### 许可（使用全库前必读）

- **Catalogue of Life**：遵循 [COL 许可与引用要求](https://www.catalogueoflife.org/)（版本与条款以官方为准）
- **GBIF Backbone / 衍生数据**：遵循 [GBIF 数据使用协议](https://www.gbif.org/terms)
- **中文俗名**：需单独授权来源；样本库中的中文名为演示用，不构成权威译名

应用内页脚 / 关于应标明实际加载库的 `source` 与 `license`（见 SQLite `meta` 表）。

## 为何不用巨型 JSON

全库进内存会压垮手机 WebView。本应用用 **SQLite + 按窗查询**；AI 只改 HTML/JS/CSS 壳，不生成全库。
