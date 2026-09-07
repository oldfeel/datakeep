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
  rm -f "$out"

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
        -x './.DS_Store' \
        -x '*/.DS_Store' \
        -x './data/*' \
        -x './data/**' \
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
fi
