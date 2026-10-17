#!/usr/bin/env bash
# 打包 examples/*-app 到 examples/dist/<id>-<version>.zip（id 为包名，如 site.datakeep.hello）
# 含 package.json 的应用：先 npm run build，再只打 www/ 内容。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
mkdir -p "$DIST"

pack_one() {
  local dir="$1"
  local app_json="$dir/app.json"
  if [[ ! -f "$app_json" ]]; then
    echo "跳过（无 app.json）: $dir" >&2
    return 0
  fi
  local id version out
  id="$(python3 -c "import json;print(json.load(open('$app_json'))['id'])")"
  version="$(python3 -c "import json;print(json.load(open('$app_json'))['version'])")"
  out="$DIST/${id}-${version}.zip"
  # 删除同 id 的旧版 zip（升 version 后留下的遗留包）
  local old
  for old in "$DIST/${id}-"*.zip; do
    [[ -f "$old" ]] || continue
    if [[ "$old" != "$out" ]]; then
      echo "删除遗留包: $old" >&2
    fi
    rm -f "$old"
  done

  if [[ -f "$dir/package.json" ]]; then
    echo "构建 Vite 应用: $dir" >&2
    (
      cd "$dir"
      if [[ -f package-lock.json ]]; then
        npm ci
      else
        npm install
      fi
      npm run build
    )
    if [[ ! -f "$dir/www/index.html" ]]; then
      echo "错误: 构建后缺少 www/index.html: $dir" >&2
      return 1
    fi
    if [[ ! -f "$dir/www/app.json" ]]; then
      echo "警告: www/ 缺少 app.json，正在从包根拷贝" >&2
      cp "$dir/app.json" "$dir/www/app.json"
    fi
    (
      cd "$dir/www"
      zip -r "$out" . \
        -x './.DS_Store' \
        -x '*/.DS_Store'
    )
  else
    (
      cd "$dir"
      # 包内不要 README；保留 app 运行所需文件
      zip -r "$out" . \
        -x './README.md' \
        -x './DATA.md' \
        -x './.DS_Store' \
        -x '*/.DS_Store' \
        -x './data/*' \
        -x './data/**' \
        -x './scripts/*' \
        -x './scripts/**' \
        -x './node_modules/*' \
        -x './node_modules/**' \
        -x './src/*' \
        -x './src/**' \
        -x './www/*' \
        -x './www/**'
    )
  fi
  echo "已生成: $out ($(wc -c <"$out") bytes)"
}

if [[ $# -gt 0 ]]; then
  for name in "$@"; do
    pack_one "$ROOT/$name"
  done
else
  for d in "$ROOT"/*-app; do
    [[ -d "$d" ]] || continue
    pack_one "$d"
  done
  # 全量打包：清掉已无对应 examples/*-app 的残留 zip
  python3 - "$DIST" "$ROOT" <<'PY'
import json, sys
from pathlib import Path
dist, root = Path(sys.argv[1]), Path(sys.argv[2])
keep = set()
for app_json in root.glob("*-app/app.json"):
    try:
        keep.add(json.loads(app_json.read_text())["id"])
    except Exception:
        pass
for z in dist.glob("*.zip"):
    # 文件名: <id>-<version>.zip；id 含点，取最后一个 - 前为 id 不可靠，
    # 用「是否以已知 id- 开头」判断。
    name = z.name
    if not any(name.startswith(i + "-") and name.endswith(".zip") for i in keep):
        print(f"删除无应用遗留包: {z}", file=sys.stderr)
        z.unlink(missing_ok=True)
PY
fi
