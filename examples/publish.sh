#!/usr/bin/env bash
# 打包 examples/*-app 并上传到应用市场（默认 https://admin.datakeep.site）
#
# 用法:
#   ./publish.sh video-app                 # 用当前 app.json 版本打包上传
#   ./publish.sh video-app 1.0.1           # 先升到指定版本再上传
#   ./publish.sh video-app --bump patch    # patch(+0.0.1)/minor/major 自增后上传
#   ./publish.sh video-app --dry-run       # 只打包不上传
#
# 账号（勿提交；examples/.env 已在 .gitignore）:
#   examples/.env 中 ACCOUNT=… / PASSWORD=…
#   或 DATAKEEP_MARKET_USER / DATAKEEP_MARKET_PASSWORD / DATAKEEP_MARKET_TOKEN
#   或旁路 ../datakeep-market/market_server/.env 的 ADMIN_*
#   DATAKEEP_MARKET_URL 默认 https://admin.datakeep.site
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
DIST="$ROOT/dist"
MARKET_URL="${DATAKEEP_MARKET_URL:-https://admin.datakeep.site}"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令: $1" >&2
    exit 1
  }
}

# 解析单个 .env 文件，写入 DATAKEEP_MARKET_USER / PASSWORD（不覆盖已有）
_load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 1
  local line k v
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"
    v="${line#*=}"
    k="${k%"${k##*[![:space:]]}"}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [[ ${#v} -ge 2 ]]; then
      if [[ ( "${v:0:1}" == '"' && "${v: -1}" == '"' ) || ( "${v:0:1}" == "'" && "${v: -1}" == "'" ) ]]; then
        v="${v:1:-1}"
      fi
    fi
    case "$k" in
      ACCOUNT|ACCTION|USER|USERNAME|ADMIN_USERNAME|DATAKEEP_MARKET_USER)
        [[ -z "${DATAKEEP_MARKET_USER:-}" ]] && DATAKEEP_MARKET_USER="$v"
        ;;
      PASSWORD|ADMIN_PASSWORD|DATAKEEP_MARKET_PASSWORD)
        [[ -z "${DATAKEEP_MARKET_PASSWORD:-}" ]] && DATAKEEP_MARKET_PASSWORD="$v"
        ;;
      DATAKEEP_MARKET_TOKEN|TOKEN)
        [[ -z "${DATAKEEP_MARKET_TOKEN:-}" ]] && DATAKEEP_MARKET_TOKEN="$v"
        ;;
      DATAKEEP_MARKET_URL|MARKET_URL)
        [[ "$MARKET_URL" == "https://admin.datakeep.site" && -n "$v" ]] && MARKET_URL="$v"
        ;;
    esac
  done < "$env_file"
  return 0
}

load_market_creds() {
  # 优先本目录 examples/.env，再旁路 market_server/.env
  _load_env_file "$ROOT/.env" || true
  if [[ -z "${DATAKEEP_MARKET_USER:-}" || -z "${DATAKEEP_MARKET_PASSWORD:-}" ]]; then
    local fallback="${DATAKEEP_MARKET_ENV:-$REPO_ROOT/../datakeep-market/market_server/.env}"
    _load_env_file "$fallback" || true
  fi
  [[ -n "${DATAKEEP_MARKET_USER:-}" && -n "${DATAKEEP_MARKET_PASSWORD:-}" ]] \
    || [[ -n "${DATAKEEP_MARKET_TOKEN:-}" ]]
}

market_login_token() {
  if [[ -n "${DATAKEEP_MARKET_TOKEN:-}" ]]; then
    printf '%s' "$DATAKEEP_MARKET_TOKEN"
    return 0
  fi
  if [[ -z "${DATAKEEP_MARKET_USER:-}" || -z "${DATAKEEP_MARKET_PASSWORD:-}" ]]; then
    load_market_creds || true
  fi
  local user="${DATAKEEP_MARKET_USER:-}"
  local pass="${DATAKEEP_MARKET_PASSWORD:-}"
  if [[ -z "$user" || -z "$pass" ]]; then
    echo "未配置市场账号。请在 examples/.env 写 ACCOUNT / PASSWORD" >&2
    return 1
  fi
  need_cmd curl
  local body resp
  if command -v jq >/dev/null 2>&1; then
    body="$(jq -n --arg u "$user" --arg p "$pass" '{username:$u,password:$p}')"
  else
    body="$(printf '{"username":"%s","password":"%s"}' \
      "${user//\"/\\\"}" "${pass//\"/\\\"}")"
  fi
  resp="$(curl -fsS -X POST "$MARKET_URL/admin/login" \
    -H 'Content-Type: application/json' \
    -d "$body")" || {
    echo "登录失败: $MARKET_URL/admin/login" >&2
    return 1
  }
  if command -v jq >/dev/null 2>&1; then
    local code token
    code="$(echo "$resp" | jq -r '.code')"
    token="$(echo "$resp" | jq -r '.data.token // empty')"
    if [[ "$code" != "0" || -z "$token" || "$token" == "null" ]]; then
      echo "登录失败: $resp" >&2
      return 1
    fi
    printf '%s' "$token"
  else
    echo "$resp" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
  fi
}

# 同步写入 app.json / public/app.json / package.json 的 version
set_app_version() {
  local dir="$1"
  local ver="$2"
  need_cmd python3
  python3 - "$dir" "$ver" <<'PY'
import json, sys
from pathlib import Path
dir_path = Path(sys.argv[1])
ver = sys.argv[2]
for rel in ("app.json", "public/app.json", "package.json"):
    p = dir_path / rel
    if not p.is_file():
        continue
    data = json.loads(p.read_text(encoding="utf-8"))
    data["version"] = ver
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已写版本 {ver} → {p}", file=sys.stderr)
PY
}

bump_semver() {
  local cur="$1"
  local kind="$2" # patch | minor | major
  python3 - "$cur" "$kind" <<'PY'
import sys
cur, kind = sys.argv[1], sys.argv[2]
parts = [int(x) for x in cur.split(".")]
while len(parts) < 3:
    parts.append(0)
parts = parts[:3]
if kind == "major":
    parts = [parts[0] + 1, 0, 0]
elif kind == "minor":
    parts = [parts[0], parts[1] + 1, 0]
else:
    parts = [parts[0], parts[1], parts[2] + 1]
print(".".join(str(x) for x in parts))
PY
}

publish_zip() {
  local zip_path="$1"
  local expect_key="$2"
  local token
  token="$(market_login_token)" || return 1
  need_cmd curl
  echo "上传: $zip_path → $MARKET_URL/admin/apps/publish" >&2
  local resp
  resp="$(curl -fsS -X POST "$MARKET_URL/admin/apps/publish" \
    -H "Authorization: Bearer $token" \
    -F "file=@${zip_path};type=application/zip" \
    -F "confirmOverwrite=1" \
    -F "expectAppKey=${expect_key}")" || {
    echo "上传请求失败" >&2
    return 1
  }
  if command -v jq >/dev/null 2>&1; then
    local code
    code="$(echo "$resp" | jq -r '.code')"
    if [[ "$code" != "0" ]]; then
      echo "上传失败: $resp" >&2
      return 1
    fi
    echo "$resp" | jq -r '
      "已发布: \(.data.meta.id) v\(.data.meta.version) (\(.data.meta.name))"
      + (if .data.created then " [新建]" else " [覆盖]" end)
    '
  else
    echo "$resp"
  fi
}

APP_NAME=""
TARGET_VERSION=""
BUMP_KIND=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --bump)
      BUMP_KIND="${2:-}"
      [[ "$BUMP_KIND" =~ ^(patch|minor|major)$ ]] || {
        echo "--bump 需为 patch|minor|major" >&2
        exit 1
      }
      shift 2
      ;;
    -*)
      echo "未知参数: $1" >&2
      usage 1
      ;;
    *)
      if [[ -z "$APP_NAME" ]]; then
        APP_NAME="$1"
      elif [[ -z "$TARGET_VERSION" ]]; then
        TARGET_VERSION="$1"
      else
        echo "多余参数: $1" >&2
        usage 1
      fi
      shift
      ;;
  esac
done

[[ -n "$APP_NAME" ]] || usage 1
[[ -z "$TARGET_VERSION" || -z "$BUMP_KIND" ]] || {
  echo "不能同时指定版本号与 --bump" >&2
  exit 1
}

APP_DIR="$ROOT/$APP_NAME"
APP_JSON="$APP_DIR/app.json"
[[ -f "$APP_JSON" ]] || {
  echo "找不到应用: $APP_DIR/app.json" >&2
  exit 1
}

CUR_VER="$(python3 -c "import json;print(json.load(open('$APP_JSON'))['version'])")"
APP_ID="$(python3 -c "import json;print(json.load(open('$APP_JSON'))['id'])")"

if [[ -n "$BUMP_KIND" ]]; then
  TARGET_VERSION="$(bump_semver "$CUR_VER" "$BUMP_KIND")"
fi
if [[ -n "$TARGET_VERSION" ]]; then
  set_app_version "$APP_DIR" "$TARGET_VERSION"
  CUR_VER="$TARGET_VERSION"
fi

echo "应用: $APP_NAME ($APP_ID) v$CUR_VER" >&2
"$ROOT/pack.sh" "$APP_NAME"

ZIP="$DIST/${APP_ID}-${CUR_VER}.zip"
[[ -f "$ZIP" ]] || {
  echo "打包产物不存在: $ZIP" >&2
  exit 1
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run：已生成 $ZIP，跳过上传" >&2
  exit 0
fi

publish_zip "$ZIP" "$APP_ID"
echo "官网应用页: https://datakeep.site/apps" >&2
echo "管理后台: $MARKET_URL/" >&2
