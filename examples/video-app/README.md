# 视频

符合 [应用包规范](../../docs/app-package-spec.md)。

本地视频库（**Vite + React + MUI + Editor.js**）：三级分类（一级 / 二级 / 合集）+ 视频条目（标题、描述、封面），支持搜索。

## 目录约定

```text
examples/video-app/
  app.json / package.json / src / public / www/   # 源码与构建产物

data/                                            # 用户数据（安装目录，不进 zip）
  <一级>/
    <二级>/
      <合集可选>/
        <entryId>/
          video.<ext>      # 添加时从本机复制进库
          cover.jpg        # 生成或自选封面
          meta.json        # 标题、Editor.js 描述等
```

`meta.json` 示例：

```json
{
  "title": "Big Buck Bunny",
  "description": { "time": 0, "blocks": [], "version": "2.x.x" },
  "cover": "cover.jpg",
  "video": "video.mp4",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601"
}
```

- `description` 为 [Editor.js](https://editorjs.io/) `OutputData`（与 Saleor 产品富文本同协议）。
- 站外选中的视频/封面会 **复制** 进条目目录；原文件不动。播放只读 `data/` 内文件。
- 应用更新不会覆盖已有 `data/`。
- 旧式裸视频文件仍可只读展示（标题=文件名）。

## UI

- **侧栏**：一级分类 +「添加分类」
- **右侧顶栏**：二级 Chips、「添加视频」、搜索、排序
- **视频列表**：无合集的视频单独成卡；同合集多集折叠为一张**剧集卡**（名称 / 集数 / 封面），点进后再列各集
- **添加 / 编辑**：一级/二级/合集名、标题、视频、封面、描述（共用表单）

## 开发

```bash
cd examples/video-app
npm install
npm run build    # 首次
npm run dev      # vite build --watch → www/
```

Debug 下 Flutter AppRunner 直连 `www/`，`data/` 用安装目录。改前端后约 2 秒自动重载。

```bash
cd examples && ./pack.sh video-app
```
