#!/usr/bin/env bash
# 打包 examples/*-app 到 examples/dist/<id>-<version>.zip（id 为包名，如 site.datakeep.hello）
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
  (
    cd "$dir"
    # 包内不要 README；保留 app 运行所需文件
    zip -r "$out" . \
      -x './README.md' \
      -x './.DS_Store' \
      -x '*/.DS_Store' \
      -x './data/*' \
      -x './data/**'
  )
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
