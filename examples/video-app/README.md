# 视频

符合 [应用包规范](../../docs/app-package-spec.md)。

本地视频库：扫描 `data/`，左侧为 **全部 / 合集（一级子文件夹）**，右侧为合集或视频网格；点击用 HTML5 `<video>` 播放。

## 目录约定

```text
data/
  开源电影/          # 左栏合集名
    BigBuckBunny.mp4
    Sintel.mkv
  短片/
    …
  loose.mp4          # 未分类（根目录视频）
```

- 应用更新不会覆盖已有 `data/`。
- **不要**把演示成片打进上架 zip（`pack.sh` 已排除 `data/`）。

## 演示素材（自行下载，1080p 开源电影）

放到本机例如 `~/下载/datakeep-demo-videos/开源电影/`，再复制或软链到已安装应用的 `data/开源电影/`：

| 片名 | 直链 |
|------|------|
| Big Buck Bunny | https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_1080p_h264.mov.zip |
| Sintel | https://download.blender.org/demo/movies/Sintel.2010.1080p.mkv |
| Tears of Steel | https://download.blender.org/demo/movies/ToS/tears_of_steel_1080p.mov.zip |

zip 需解压。合集请用「开源电影」等中性名称，勿挂未授权院线/美剧片名用于公开宣传。

索引目录：

- https://download.blender.org/peach/bigbuckbunny_movies/
- https://download.blender.org/demo/movies/
- https://download.blender.org/demo/movies/ToS/

## 后续

音频、图片、故事/小说/听书将做成**独立应用**，本期不做。

## 打包

```bash
cd examples && ./pack.sh video-app
# => dist/site.datakeep.video-1.0.0.zip
```

须在 DataKeep 客户端 AppRunner 内打开。上架：管理后台上传 zip。
