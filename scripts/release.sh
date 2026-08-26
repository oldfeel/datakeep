#!/usr/bin/env bash
# DataKeep 发版：更新版本 → 打 tag → 推送 → 触发 GitHub Actions 多平台编译
# 编完后可选：通知官网从 GitHub Release 拉取并写入 GitHub 下载链 + 生成 BT 种子
#
# 用法:
#   ./scripts/release.sh              # 默认 patch：末位 +1，逢 10 进位（0.0.9 → 0.1.0，不会出现 0.0.10）
#   ./scripts/release.sh 1.2.0        # 设为指定版本（build+1）并发版
#   ./scripts/release.sh patch        # 同默认：修订号 +1（十进制进位）
#   ./scripts/release.sh minor        # 次版本 +1（0.0.x → 0.1.0；次位逢 10 进主版本）
#   ./scripts/release.sh major        # 主版本 +1（0.x.y → 1.0.0）
#   ./scripts/release.sh --dry-run    # 只打印将要做的事
#   ./scripts/release.sh --no-wait    # 推送后不等待 CI
#   ./scripts/release.sh --local      # 不打远程 tag，仅本机 ./scripts/build.sh
#   ./scripts/release.sh --skip-market     # 不等待/不同步官网
#   ./scripts/release.sh market           # 仅把已有 GitHub Release 同步到官网（默认最新 tag）
#   ./scripts/release.sh market v0.0.2    # 指定 tag（qiniu/sync 为同义别名）
#   ./scripts/release.sh links            # 打印最新 Release 四端 GitHub 下载链接
#   ./scripts/release.sh links v0.0.3     # 指定 tag
#   ./scripts/release.sh torrents         # 打印官网四端磁力链（需先 sync-github）
#   ./scripts/release.sh torrents v0.0.3  # 指定版本（仅校验 tag，链来自当前官网 API）
#   ./scripts/release.sh download         # 下载四端包 + .torrent 到 dist-release/（默认最新 tag）
#   ./scripts/release.sh download v0.0.4  # 指定 tag
#   ./scripts/release.sh --proxy           # 等待 CI / gh 走本机代理（同 download）
#   DATAKEEP_USE_PROXY=1 ./scripts/release.sh download v0.0.4  # 走本机代理（默认 127.0.0.1:7897）
#   ./scripts/release.sh download v0.0.6 --torrents-only      # 仅补拉 .torrent（安装包已有时）
#   ./scripts/release.sh download v0.0.6 --skip-pgyer         # 跳过上传 APK 到蒲公英
#
# 官网同步（编完后默认尝试）:
#   优先读环境变量 DATAKEEP_MARKET_TOKEN / USER / PASSWORD
#   否则自动读旁路仓库 ../datakeep-market/market_server/.env 的 ADMIN_USERNAME/PASSWORD
#   DATAKEEP_MARKET_URL 默认 https://admin.datakeep.site
#   DATAKEEP_MARKET_ENV  可指定 .env 路径
#
# 蒲公英（download 完成后自动上传 Android APK）:
#   PGYER_API_KEY  或旁路 ../datakeep-market/market_server/.env 的 PGYER_API_KEY
#   也可 ~/.config/pgyer/config.json 的 apiKey（pgyer-cli 格式）
#   DATAKEEP_SKIP_PGYER=1 或 --skip-pgyer 跳过
#
# 远程发版依赖公开仓 workflow「Build packages」（push tags: v*）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/datakeep_flutter"
PUBSPEC="$APP_DIR/pubspec.yaml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

DRY_RUN=0
NO_WAIT=0
LOCAL_ONLY=0
SKIP_MARKET=0
MODE="patch" # 默认末位 +1（十进制进位）；可被 patch|minor|major|x.y.z 覆盖
ACTION="release" # release | market | links | torrents | download
RELEASE_TAG=""
USE_PROXY=0
TORRENTS_ONLY=0
SKIP_PGYER="${DATAKEEP_SKIP_PGYER:-0}"

MARKET_URL="${DATAKEEP_MARKET_URL:-https://admin.datakeep.site}"
MARKET_URL="${MARKET_URL%/}"
PUBLIC_SITE="${DATAKEEP_PUBLIC_SITE:-https://datakeep.site}"
PUBLIC_SITE="${PUBLIC_SITE%/}"

usage() {
  cat <<'EOF'
DataKeep 发版：版本 +0.0.1 → 打 tag → 推送 → 触发 GitHub Actions 多平台编译
编完后默认调用官网接口：服务器从 GitHub Release 拉包、写入 GitHub 链并生成 BT 种子与磁力链。

用法:
  ./scripts/release.sh              # 默认末位 +1（0.0.8 → 0.0.9 → 0.1.0，无 0.0.10）
  ./scripts/release.sh 1.2.0        # 设为指定版本（build+1）并发版
  ./scripts/release.sh patch        # 同默认（十进制进位）
  ./scripts/release.sh minor        # 次版本 +1（次位逢 10 进主版本）
  ./scripts/release.sh major        # 主版本 +1
  ./scripts/release.sh --dry-run    # 只打印将要做的事
  ./scripts/release.sh --no-wait    # 推送后不等待 CI
  ./scripts/release.sh --local      # 不打远程 tag，仅本机 ./scripts/build.sh
  ./scripts/release.sh --skip-market     # 不同步官网
  ./scripts/release.sh market            # 仅同步已有 Release → 官网（最新 tag）
  ./scripts/release.sh market v0.0.2     # 指定 tag 同步（qiniu/sync 为别名）
  ./scripts/release.sh links             # 打印四端 GitHub 下载直链（默认最新 tag）
  ./scripts/release.sh links v0.0.3      # 指定 tag
  ./scripts/release.sh torrents          # 打印四端磁力链（从官网 API，需先 sync）
  ./scripts/release.sh torrents v0.0.3   # 指定版本校验后打印磁力链
  ./scripts/release.sh download            # 下载四端到 dist-release/（默认最新 tag）
  ./scripts/release.sh download v0.0.4     # 指定 tag
  DATAKEEP_USE_PROXY=1 ./scripts/release.sh download v0.0.4
    # 或先 export https_proxy=http://127.0.0.1:7897 http_proxy=... all_proxy=...
  ./scripts/release.sh download v0.0.6 --torrents-only   # 仅补拉 .torrent
  ./scripts/release.sh download v0.0.6 --skip-pgyer        # 不上传蒲公英

官网同步：默认用旁路 datakeep-market/market_server/.env 的 ADMIN_*；
也可设 DATAKEEP_MARKET_TOKEN，或 DATAKEEP_MARKET_USER + DATAKEEP_MARKET_PASSWORD。

蒲公英：download 完成后自动上传 APK；设 PGYER_API_KEY（或 .env / ~/.config/pgyer/config.json）。
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    -h|--help|help) usage ;;
    --dry-run) DRY_RUN=1 ;;
    --no-wait) NO_WAIT=1 ;;
    --local) LOCAL_ONLY=1 ;;
    --skip-market) SKIP_MARKET=1 ;;
    --proxy) USE_PROXY=1 ;;
    --no-proxy) USE_PROXY=0 ;;
    --torrents-only) TORRENTS_ONLY=1 ;;
    --skip-pgyer) SKIP_PGYER=1 ;;
    qiniu|sync|market)
      ACTION="market"
      ;;
    links|urls)
      ACTION="links"
      ;;
    torrents|magnets)
      ACTION="torrents"
      ;;
    download|fetch|seed-prep|dist-release)
      ACTION="download"
      ;;
    v[0-9]*.[0-9]*.[0-9]*)
      if [[ "$ACTION" == "market" || "$ACTION" == "links" || "$ACTION" == "torrents" || "$ACTION" == "download" ]]; then
        RELEASE_TAG="$arg"
      else
        # 当版本号写成 v1.2.0 时按 1.2.0 发版
        MODE="${arg#v}"
      fi
      ;;
    patch|minor|major) MODE="$arg" ;;
    [0-9]*.[0-9]*.[0-9]*) MODE="$arg" ;;
    *)
      err "未知参数: $arg"
      usage
      ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "需要命令: $1"
    exit 1
  }
}

# 从 market_server/.env 读 ADMIN_USERNAME / ADMIN_PASSWORD（不覆盖已有环境变量）
load_market_creds_from_env_file() {
  local env_file="${DATAKEEP_MARKET_ENV:-}"
  if [[ -z "$env_file" ]]; then
    env_file="$ROOT/../datakeep-market/market_server/.env"
  fi
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
      ADMIN_USERNAME)
        if [[ -z "${DATAKEEP_MARKET_USER:-}" ]]; then
          DATAKEEP_MARKET_USER="$v"
        fi
        ;;
      ADMIN_PASSWORD)
        if [[ -z "${DATAKEEP_MARKET_PASSWORD:-}" ]]; then
          DATAKEEP_MARKET_PASSWORD="$v"
        fi
        ;;
    esac
  done < "$env_file"
  [[ -n "${DATAKEEP_MARKET_USER:-}" && -n "${DATAKEEP_MARKET_PASSWORD:-}" ]]
}

# 蒲公英 API Key：PGYER_API_KEY > market .env > ~/.config/pgyer/config.json
load_pgyer_api_key() {
  [[ -n "${PGYER_API_KEY:-}" ]] && return 0

  local env_file="${DATAKEEP_MARKET_ENV:-}"
  if [[ -z "$env_file" ]]; then
    env_file="$ROOT/../datakeep-market/market_server/.env"
  fi
  if [[ -f "$env_file" ]]; then
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
      if [[ "$k" == "PGYER_API_KEY" && -n "$v" ]]; then
        PGYER_API_KEY="$v"
        return 0
      fi
    done < "$env_file"
  fi

  local cfg="${PGYER_CONFIG_FILE:-${HOME}/.config/pgyer/config.json}"
  if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
    local key
    key="$(jq -r '.apiKey // empty' "$cfg" 2>/dev/null || true)"
    if [[ -n "$key" && "$key" != "null" ]]; then
      PGYER_API_KEY="$key"
      return 0
    fi
  fi

  return 1
}

# 蒲公英快速上传（getCOSToken → COS → buildInfo）
upload_apk_to_pgyer() {
  local apk="$1" tag="$2"
  local api_base="${PGYER_API_BASE:-https://api.pgyer.com/apiv2}"
  local api_key="$PGYER_API_KEY"
  local desc result code endpoint build_key upload_key signature cos_token http_code
  local i shortcut_url build_version

  need_cmd curl
  need_cmd jq

  desc="DataKeep ${tag}"

  log "上传 APK 到蒲公英: $(basename "$apk")"

  result="$(curl -fsS --form-string "_api_key=${api_key}" \
    --form-string "buildType=apk" \
    --form-string "buildUpdateDescription=${desc}" \
    "${api_base}/app/getCOSToken")" || {
    err "蒲公英 getCOSToken 请求失败"
    return 1
  }
  code="$(echo "$result" | jq -r '.code // empty')"
  if [[ "$code" != "0" ]]; then
    err "蒲公英 getCOSToken 失败: $(echo "$result" | jq -r '.message // .data // .')"
    return 1
  fi

  endpoint="$(echo "$result" | jq -r '.data.endpoint // empty')"
  build_key="$(echo "$result" | jq -r '.data.key // empty')"
  upload_key="$(echo "$result" | jq -r '.data.params.key // empty')"
  signature="$(echo "$result" | jq -r '.data.params.signature // empty')"
  cos_token="$(echo "$result" | jq -r '.data.params["x-cos-security-token"] // empty')"
  if [[ -z "$endpoint" || -z "$build_key" || -z "$upload_key" || -z "$signature" || -z "$cos_token" ]]; then
    err "蒲公英 getCOSToken 响应不完整"
    return 1
  fi

  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 30 --max-time 1800 \
    --form-string "key=${upload_key}" \
    --form-string "signature=${signature}" \
    --form-string "x-cos-security-token=${cos_token}" \
    --form-string "x-cos-meta-file-name=$(basename "$apk")" \
    -F "file=@${apk}" \
    "${endpoint}")" || {
    err "蒲公英 COS 上传失败"
    return 1
  }
  if [[ "$http_code" != "204" ]]; then
    err "蒲公英 COS 上传失败 HTTP ${http_code}"
    return 1
  fi

  ok "APK 已上传，等待蒲公英处理…"
  for i in $(seq 1 60); do
    result="$(curl -fsS -G \
      --data-urlencode "_api_key=${api_key}" \
      --data-urlencode "buildKey=${build_key}" \
      "${api_base}/app/buildInfo")" || {
      sleep 1
      continue
    }
    code="$(echo "$result" | jq -r '.code // empty')"
    if [[ "$code" == "0" ]]; then
      shortcut_url="$(echo "$result" | jq -r '.data.buildShortcutUrl // empty')"
      build_version="$(echo "$result" | jq -r '.data.buildVersion // empty')"
      ok "蒲公英构建完成: ${build_version:-$tag}"
      if [[ -n "$shortcut_url" ]]; then
        ok "下载: https://www.pgyer.com/${shortcut_url}"
        ok "二维码: https://www.pgyer.com/app/qrcode/${shortcut_url}"
      fi
      return 0
    fi
    sleep 1
  done

  err "蒲公英构建超时（60s）"
  return 1
}

market_login_token() {
  if [[ -n "${DATAKEEP_MARKET_TOKEN:-}" ]]; then
    printf '%s' "$DATAKEEP_MARKET_TOKEN"
    return 0
  fi
  if [[ -z "${DATAKEEP_MARKET_USER:-}" || -z "${DATAKEEP_MARKET_PASSWORD:-}" ]]; then
    load_market_creds_from_env_file || true
  fi
  local user="${DATAKEEP_MARKET_USER:-}"
  local pass="${DATAKEEP_MARKET_PASSWORD:-}"
  if [[ -z "$user" || -z "$pass" ]]; then
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
    -d "$body")" || return 1
  if command -v jq >/dev/null 2>&1; then
    local code token
    code="$(echo "$resp" | jq -r '.code')"
    token="$(echo "$resp" | jq -r '.data.token // empty')"
    [[ "$code" == "0" && -n "$token" && "$token" != "null" ]] || return 1
    printf '%s' "$token"
  else
    echo "$resp" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
  fi
}

sync_market_from_github() {
  local token="$1"
  need_cmd curl
  log "通知官网从 GitHub Release 同步到市场服务器（${MARKET_URL}）…"
  local start_resp
  start_resp="$(curl -fsS -X POST "$MARKET_URL/admin/client-releases/sync-github" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "$(printf '{"tag":"%s","repo":"%s"}' "$TAG" "$REPO")")" || {
    err "触发同步失败（请确认线上 market_server 已部署 sync-github 接口）"
    return 1
  }
  if command -v jq >/dev/null 2>&1; then
    local code
    code="$(echo "$start_resp" | jq -r '.code')"
    if [[ "$code" != "0" ]]; then
      err "触发同步失败: $(echo "$start_resp" | jq -r '.data')"
      return 1
    fi
  fi
  ok "同步任务已启动，等待服务器完成（GitHub 拉包，可能较久）…"

  local i status msg
  for i in $(seq 1 180); do
    sleep 5
    local st
    st="$(curl -fsS "$MARKET_URL/admin/client-releases/sync-github/status" \
      -H "Authorization: Bearer $token")" || continue
    if ! command -v jq >/dev/null 2>&1; then
      echo "$st"
      warn "未安装 jq，无法自动判断完成状态，请到管理后台确认"
      return 0
    fi
    status="$(echo "$st" | jq -r '.data.status')"
    msg="$(echo "$st" | jq -r '.data.message // empty')"
    case "$status" in
      ok)
        ok "官网同步完成: $msg"
        echo "$st" | jq -r '.data.results[]? | "  - \(.platform): \(.fileName) (\(.size) bytes)"' 2>/dev/null || true
        return 0
        ;;
      error)
        err "官网同步失败: $msg"
        return 1
        ;;
      running|idle)
        log "同步中… ($msg)"
        ;;
    esac
  done
  err "等待官网同步超时（仍可能在后台进行，可查 status 接口）"
  return 1
}

resolve_repo() {
  git -C "$ROOT" remote get-url origin | sed -E 's#.*github.com[:/]([^/]+/[^/.]+)(\.git)?#\1#'
}

# 查找 tag 发版触发的 workflow run（commit / tag / 最近列表 三重兜底）
find_workflow_run_id() {
  local repo="$1" tag="$2" sha="$3"
  local id=""

  id="$(gh run list --repo "$repo" --workflow=build.yml --commit "$sha" --limit 1 \
    --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  if [[ -n "$id" && "$id" != "null" ]]; then
    printf '%s' "$id"
    return 0
  fi

  id="$(gh run list --repo "$repo" --workflow=build.yml --branch "$tag" --limit 1 \
    --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  if [[ -n "$id" && "$id" != "null" ]]; then
    printf '%s' "$id"
    return 0
  fi

  id="$(gh run list --repo "$repo" --workflow=build.yml --limit 15 \
    --json databaseId,headBranch,headSha -q \
    ".[] | select(.headBranch==\"$tag\" or .headSha==\"$sha\") | .databaseId" 2>/dev/null | head -1 || true)"
  if [[ -n "$id" && "$id" != "null" ]]; then
    printf '%s' "$id"
    return 0
  fi

  return 1
}

resolve_release_tag() {
  local tag="${RELEASE_TAG:-}"
  if [[ -z "$tag" ]]; then
    tag="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
    if [[ -z "$tag" ]] && command -v gh >/dev/null 2>&1; then
      tag="$(gh release list --repo "$REPO" --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)"
    fi
  fi
  if [[ -z "$tag" ]]; then
    return 1
  fi
  [[ "$tag" == v* ]] || tag="v$tag"
  printf '%s' "$tag"
}

# 下载子命令：可走 https_proxy / DATAKEEP_USE_PROXY=1（默认 127.0.0.1:7897）
apply_download_proxy() {
  if [[ "$USE_PROXY" -eq 1 ]] || [[ "${DATAKEEP_USE_PROXY:-}" == "1" || "${DATAKEEP_USE_PROXY:-}" == "true" ]]; then
    export https_proxy="${https_proxy:-${HTTPS_PROXY:-${DATAKEEP_HTTPS_PROXY:-http://127.0.0.1:7897}}}"
    export http_proxy="${http_proxy:-${HTTP_PROXY:-${DATAKEEP_HTTP_PROXY:-$https_proxy}}}"
    export all_proxy="${all_proxy:-${ALL_PROXY:-${DATAKEEP_ALL_PROXY:-socks5://127.0.0.1:7897}}}"
    export HTTPS_PROXY="$https_proxy"
    export HTTP_PROXY="$http_proxy"
    export ALL_PROXY="$all_proxy"
    log "使用代理: $https_proxy"
  elif [[ -n "${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
    log "使用环境代理: ${https_proxy:-$HTTPS_PROXY}"
  fi
}

# 访问官网 API（带重试；失败返回非 0）
curl_public_site() {
  local url="$1"
  local out="${2:-}"
  local label="${3:-$url}"
  local tries="${DATAKEEP_CURL_RETRIES:-5}"
  local delay=2
  local i

  for ((i = 1; i <= tries; i++)); do
    if [[ -n "$out" ]]; then
      if curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 20 --max-time 180 \
        "$url" -o "$out"; then
        return 0
      fi
    else
      if curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 20 --max-time 180 \
        "$url"; then
        return 0
      fi
    fi
    if [[ "$i" -lt "$tries" ]]; then
      warn "${label} 失败，${delay}s 后重试 (${i}/${tries})…"
      sleep "$delay"
      if [[ "$delay" -lt 30 ]]; then
        delay=$((delay * 2))
      fi
    fi
  done
  return 1
}

cmd_download() {
  cd "$ROOT"
  REPO="$(resolve_repo)"
  local tag ver out packages torrents magnets
  if ! tag="$(resolve_release_tag)"; then
    err "无法确定 tag。请指定: ./scripts/release.sh download v0.0.4"
    exit 1
  fi
  ver="${tag#v}"
  out="$ROOT/dist-release/${tag}"
  packages="$out/packages"
  torrents="$out/torrents"
  magnets="$out/magnets.txt"

  apply_download_proxy

  log "下载 Release → $out"
  log "Repo: $REPO  Tag: $tag"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "$TORRENTS_ONLY" -eq 1 ]]; then
      warn "dry-run：将仅补拉 .torrent 到 $torrents"
    else
      warn "dry-run：将下载四端包到 ${packages}，.torrent 到 $torrents"
    fi
    exit 0
  fi

  need_cmd curl
  mkdir -p "$packages" "$torrents"

  local names=(
    "datakeep-${ver}-android.apk"
    "datakeep-${ver}-windows-x64.zip"
    "datakeep-${ver}-linux-x64.tar.gz"
    "datakeep-${ver}-macos.zip"
  )

  if [[ "$TORRENTS_ONLY" -eq 1 ]]; then
    log "仅补拉 .torrent / magnets（跳过安装包）"
  elif command -v gh >/dev/null 2>&1; then
    log "gh release download（四端安装包）…"
    gh release download "$tag" --repo "$REPO" --dir "$packages" \
      -p 'datakeep-*-android.apk' \
      -p 'datakeep-*-windows-x64.zip' \
      -p 'datakeep-*-linux-x64.tar.gz' \
      -p 'datakeep-*-macos.zip'
  else
    warn "未安装 gh，改用 curl 直链（支持断点续传 -C -）"
    local base="https://github.com/${REPO}/releases/download/${tag}"
    local name url
    for name in "${names[@]}"; do
      url="${base}/${name}"
      log "GET $name"
      curl -fL --retry 3 -C - -o "$packages/$name" "$url"
    done
  fi

  if [[ "$TORRENTS_ONLY" -eq 0 ]]; then
    local missing=""
    local name
    for name in "${names[@]}"; do
      if [[ ! -f "$packages/$name" ]]; then
        missing="${missing} ${name}"
      fi
    done
    if [[ -n "$missing" ]]; then
      err "缺少文件:${missing}"
      exit 1
    fi
  fi

  log "从官网拉取 .torrent → $torrents"
  local p tmissing="" url
  for p in android linux macos windows; do
    url="${PUBLIC_SITE}/api/client/${p}/torrent"
    if curl_public_site "$url" "$torrents/${p}.torrent" "${p} .torrent"; then
      :
    else
      tmissing="${tmissing} ${p}"
      err "未拿到 $p 的 .torrent（可先: ./scripts/release.sh market ${tag}）"
    fi
  done

  log "写入 $magnets"
  local resp=""
  if command -v jq >/dev/null 2>&1; then
    if resp="$(curl_public_site "${PUBLIC_SITE}/api/client/releases" "" "releases API")"; then
      if [[ "$(echo "$resp" | jq -r '.code')" == "0" ]]; then
        {
          echo "# DataKeep ${tag} magnets — $(date -Iseconds)"
          for p in android linux macos windows; do
            echo "$p$(echo "$resp" | jq -r --arg p "$p" '.data[] | select(.platform==$p) | "\t" + (.magnetUrl // "")')"
          done
        } >"$magnets"
      else
        warn "官网 API 返回错误，未写入 magnets.txt"
      fi
    else
      warn "无法从官网 API 写入 magnets.txt"
    fi
  else
    warn "未安装 jq，跳过 magnets.txt"
  fi

  ok "已下载到 $out"
  if [[ -d "$packages" ]] && ls "$packages"/* >/dev/null 2>&1; then
    ls -lh "$packages"
  fi
  if [[ -z "$tmissing" ]]; then
    ls -lh "$torrents"
  else
    warn "缺少 .torrent:${tmissing}"
    warn "可重试: ./scripts/release.sh download $tag --torrents-only"
    exit 1
  fi
  [[ -f "$magnets" ]] && ok "磁力链: $magnets"

  local apk="$packages/datakeep-${ver}-android.apk"
  if [[ "$SKIP_PGYER" -eq 0 && -f "$apk" ]]; then
    echo
    if load_pgyer_api_key; then
      upload_apk_to_pgyer "$apk" "$tag" || warn "蒲公英上传失败（本地下载与做种不受影响）"
    else
      warn "未配置 PGYER_API_KEY，跳过蒲公英上传（可写入 market_server/.env 或 export PGYER_API_KEY）"
    fi
  fi

  echo
  ok "做种：qBittorrent 添加 $torrents/*.torrent，数据目录指向 $packages"
  exit 0
}

cmd_links() {
  cd "$ROOT"
  REPO="$(resolve_repo)"
  local tag ver base
  if ! tag="$(resolve_release_tag)"; then
    err "无法确定 tag。请指定: ./scripts/release.sh links v0.0.3"
    exit 1
  fi
  ver="${tag#v}"
  base="https://github.com/${REPO}/releases/download/${tag}"

  printf '%s/datakeep-%s-android.apk\n' "$base" "$ver"
  printf '%s/datakeep-%s-windows-x64.zip\n' "$base" "$ver"
  printf '%s/datakeep-%s-linux-x64.tar.gz\n' "$base" "$ver"
  printf '%s/datakeep-%s-macos.zip\n' "$base" "$ver"

  if command -v gh >/dev/null 2>&1; then
    local assets_json missing=""
    local name
    if assets_json="$(gh release view "$tag" --repo "$REPO" --json assets 2>/dev/null)"; then
      for name in \
        "datakeep-${ver}-android.apk" \
        "datakeep-${ver}-windows-x64.zip" \
        "datakeep-${ver}-linux-x64.tar.gz" \
        "datakeep-${ver}-macos.zip"; do
        if ! echo "$assets_json" | jq -e --arg n "$name" '.assets[] | select(.name==$n)' >/dev/null 2>&1; then
          missing="${missing} ${name}"
        fi
      done
      if [[ -n "$missing" ]]; then
        echo -e "${YELLOW}!${NC} GitHub Release 中未找到资产:${missing}" >&2
        echo -e "${YELLOW}!${NC} CI 可能尚未传完，或 tag 与文件名版本不一致" >&2
      fi
    fi
  fi
  exit 0
}

cmd_torrents() {
  cd "$ROOT"
  need_cmd curl
  REPO="$(resolve_repo)"
  local tag ver=""
  if [[ -n "$RELEASE_TAG" ]]; then
    tag="$RELEASE_TAG"
  elif tag="$(resolve_release_tag)"; then
    :
  else
    tag=""
  fi
  if [[ -n "$tag" ]]; then
    ver="${tag#v}"
  fi

  log "从官网 API 读取磁力链（${PUBLIC_SITE}）…"
  local resp
  resp="$(curl -fsS "$PUBLIC_SITE/api/client/releases")" || {
    err "无法访问 $PUBLIC_SITE/api/client/releases"
    exit 1
  }

  if command -v jq >/dev/null 2>&1; then
    local code
    code="$(echo "$resp" | jq -r '.code')"
    if [[ "$code" != "0" ]]; then
      err "API 错误: $(echo "$resp" | jq -r '.data // empty')"
      exit 1
    fi
    local platforms=(windows macos linux android)
    local missing=""
    for p in "${platforms[@]}"; do
      local magnet api_ver
      magnet="$(echo "$resp" | jq -r --arg p "$p" '.data[] | select(.platform==$p) | .magnetUrl // empty')"
      api_ver="$(echo "$resp" | jq -r --arg p "$p" '.data[] | select(.platform==$p) | .version // empty')"
      if [[ -n "$ver" && -n "$api_ver" && "$api_ver" != "$ver" ]]; then
        warn "官网 $p 版本为 v${api_ver}，与指定 v$ver 不一致"
      fi
      if [[ -z "$magnet" ]]; then
        missing="${missing} ${p}"
        continue
      fi
      printf '%s\t%s\n' "$p" "$magnet"
    done
    if [[ -n "$missing" ]]; then
      echo -e "${YELLOW}!${NC} 缺少磁力链:${missing}（请先 ./scripts/release.sh market ${tag:-})" >&2
      exit 1
    fi
  else
    warn "未安装 jq，输出原始 JSON"
    echo "$resp"
  fi
  exit 0
}

cmd_market() {
  cd "$ROOT"
  REPO="$(resolve_repo)"
  if ! TAG="$(resolve_release_tag)"; then
    err "无法确定 tag。请指定: ./scripts/release.sh market v0.0.2"
    exit 1
  fi

  log "仅同步官网（GitHub → 写入下载链）"
  log "Repo: $REPO"
  log "Tag:  $TAG"
  log "API:  $MARKET_URL"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "dry-run：将 POST $MARKET_URL/admin/client-releases/sync-github {\"tag\":\"$TAG\",\"repo\":\"$REPO\"}"
    exit 0
  fi

  need_cmd curl
  TOKEN=""
  if ! TOKEN="$(market_login_token)" || [[ -z "$TOKEN" ]]; then
    err "未找到市场账号（旁路 datakeep-market/market_server/.env 的 ADMIN_*，或 DATAKEEP_MARKET_*）"
    exit 1
  fi
  sync_market_from_github "$TOKEN"
  ok "完成。官网下载页: https://datakeep.site/"
  exit 0
}

if [[ "$ACTION" == "links" ]]; then
  cmd_links
fi

if [[ "$ACTION" == "torrents" ]]; then
  cmd_torrents
fi

if [[ "$ACTION" == "download" ]]; then
  cmd_download
fi

if [[ "$ACTION" == "market" ]]; then
  cmd_market
fi

read_pubspec_version() {
  grep -E '^version:' "$PUBSPEC" | head -1 | awk '{print $2}'
}

# 1.0.0+3 → name=1.0.0 build=3
parse_version() {
  local full="$1"
  VER_NAME="${full%%+*}"
  if [[ "$full" == *+* ]]; then
    VER_BUILD="${full##*+}"
  else
    VER_BUILD=1
  fi
}

# 三位版本每位 0–9；进位规则类似十进制计数器（避免 0.0.10）。
# patch: 0.0.9 → 0.1.0；minor: 0.9.x → 1.0.0；major: 主版本 +1 且后两位归零。
bump_semver() {
  local kind="$1" # patch|minor|major
  local major minor patch
  IFS=. read -r major minor patch <<<"$VER_NAME"
  major=${major:-0}
  minor=${minor:-0}
  patch=${patch:-0}
  case "$kind" in
    patch)
      patch=$((patch + 1))
      if (( patch > 9 )); then
        patch=0
        minor=$((minor + 1))
      fi
      if (( minor > 9 )); then
        minor=0
        major=$((major + 1))
      fi
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      if (( minor > 9 )); then
        minor=0
        major=$((major + 1))
      fi
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
  esac
  VER_NAME="${major}.${minor}.${patch}"
  VER_BUILD=$((VER_BUILD + 1))
}

write_pubspec_version() {
  local full="$1"
  if grep -qE '^version:' "$PUBSPEC"; then
    # macOS BSD sed 需要 sed -i ''；Linux GNU sed 用 sed -i
    if [[ "$(uname -s)" == Darwin ]]; then
      sed -i '' "s/^version: .*/version: ${full}/" "$PUBSPEC"
    else
      sed -i "s/^version: .*/version: ${full}/" "$PUBSPEC"
    fi
  else
    err "pubspec.yaml 中找不到 version:"
    exit 1
  fi
}

require_clean() {
  local dirty
  dirty="$(git -C "$ROOT" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    err "工作区不干净，请先提交或暂存改动："
    echo "$dirty"
    exit 1
  fi
}

CURRENT="$(read_pubspec_version)"
parse_version "$CURRENT"

case "$MODE" in
  patch|minor|major)
    bump_semver "$MODE"
    ;;
  *)
    # 显式版本号（不走 +0.0.1）
    VER_NAME="$MODE"
    VER_BUILD=$((VER_BUILD + 1))
    ;;
esac

FULL="${VER_NAME}+${VER_BUILD}"
TAG="v${VER_NAME}"
CHANGED=1

log "当前 pubspec: $CURRENT"
log "发版版本:     $FULL  (+0.0.1 或指定版本)"
log "Git tag:      $TAG"

if git -C "$ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
  err "本地已存在 tag ${TAG}，请先 bump 版本或删除旧 tag"
  exit 1
fi
if git -C "$ROOT" ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null | grep -q "$TAG"; then
  err "远程已存在 tag $TAG"
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  warn "dry-run：不会改文件 / 打 tag / 推送"
  if [[ "$CHANGED" -eq 1 ]]; then
    echo "  将写入 pubspec version: $FULL"
  fi
  if [[ "$LOCAL_ONLY" -eq 1 ]]; then
    echo "  将执行: ./scripts/build.sh"
  else
    echo "  将: git tag $TAG && git push origin HEAD && git push origin $TAG"
    echo "  将触发 Actions: Build packages → Release"
    if [[ "$SKIP_MARKET" -eq 0 ]]; then
      echo "  将: 官网 sync-github → $MARKET_URL （tag ${TAG}）"
    fi
  fi
  exit 0
fi

cd "$ROOT"
require_clean

if [[ "$CHANGED" -eq 1 ]]; then
  write_pubspec_version "$FULL"
  git add datakeep_flutter/pubspec.yaml
  git commit -m "chore: 发版 ${TAG}（${FULL}）"
  ok "已提交版本号 $FULL"
fi

if [[ "$LOCAL_ONLY" -eq 1 ]]; then
  log "本机构建（不推送 tag）…"
  "$ROOT/scripts/build.sh"
  ok "本机构建完成，产物见 dist/"
  exit 0
fi

need_cmd git

git tag -a "$TAG" -m "Release $TAG"
ok "已创建 tag $TAG"

log "推送分支与 tag…"
git push origin HEAD
git push origin "$TAG"
ok "已推送 $TAG → 将触发 GitHub Actions「Build packages」"

REPO="$(resolve_repo)"
echo
ok "Actions: https://github.com/${REPO}/actions"
ok "Release（编完后）: https://github.com/${REPO}/releases/tag/${TAG}"

if [[ "$NO_WAIT" -eq 1 ]]; then
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  warn "未安装 gh，请到网页查看构建进度"
  exit 0
fi

apply_download_proxy

if ! gh auth status >/dev/null 2>&1; then
  warn "gh 未登录，无法跟踪 CI。请运行: gh auth login"
  warn "或设置 GH_TOKEN；发版与 CI 本身不受影响，请到 Actions 页查看"
  exit 0
fi

RELEASE_SHA="$(git -C "$ROOT" rev-parse HEAD)"
log "等待 workflow 出现（commit ${RELEASE_SHA:0:7} / ${TAG}）…"
RUN_ID=""
GH_ERR=""
for _ in $(seq 1 45); do
  if RUN_ID="$(find_workflow_run_id "$REPO" "$TAG" "$RELEASE_SHA")"; then
    break
  fi
  if [[ -z "$GH_ERR" ]]; then
    GH_ERR="$(gh run list --repo "$REPO" --workflow=build.yml --limit 1 2>&1 >/dev/null || true)"
  fi
  sleep 2
done

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  warn "暂未通过 gh 查到 workflow run（CI 可能已在跑，见上方 Actions 链接）"
  if [[ -n "$GH_ERR" ]]; then
    warn "gh 报错: ${GH_ERR//$'\n'/; }"
    if [[ "$GH_ERR" == *"auth"* || "$GH_ERR" == *"401"* ]]; then
      warn "请先: gh auth login  或 export GH_TOKEN=..."
    elif [[ "$GH_ERR" == *"timeout"* || "$GH_ERR" == *"connect"* || "$GH_ERR" == *"TLS"* ]]; then
      warn "GitHub API 可能需代理: DATAKEEP_USE_PROXY=1 ./scripts/release.sh  或 export https_proxy=..."
    fi
  fi
  warn "手动跟踪: gh run list --repo $REPO --workflow=build.yml --commit $RELEASE_SHA"
  exit 0
fi

ok "Run #$RUN_ID — 跟踪中（CEF/多平台可能较久）…"
watch_ok=0
for attempt in 1 2 3; do
  if gh run watch "$RUN_ID" --repo "$REPO" --exit-status; then
    watch_ok=1
    break
  fi
  conclusion="$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion -q .conclusion 2>/dev/null || true)"
  if [[ "$conclusion" == "success" ]]; then
    watch_ok=1
    warn "gh run watch 中断，但 workflow 已成功（GitHub API 临时故障）"
    break
  fi
  if [[ "$conclusion" == "failure" ]]; then
    break
  fi
  if [[ "$attempt" -lt 3 ]]; then
    warn "gh run watch 中断（attempt $attempt/3），5s 后重试…"
    sleep 5
  fi
done
if [[ "$watch_ok" -ne 1 ]]; then
  err "构建失败或跟踪中断，查看: gh run view $RUN_ID --repo $REPO --log-failed"
  exit 1
fi

ok "构建成功"
ok "GitHub Release: https://github.com/${REPO}/releases/tag/${TAG}"

if [[ "$SKIP_MARKET" -eq 1 ]]; then
  warn "已跳过官网同步（--skip-market）"
elif ! command -v curl >/dev/null 2>&1; then
  warn "未安装 curl，跳过官网同步"
else
  TOKEN=""
  if TOKEN="$(market_login_token)" && [[ -n "$TOKEN" ]]; then
    sync_market_from_github "$TOKEN" || warn "官网同步未成功，可稍后: ./scripts/release.sh market $TAG"
  else
    warn "未找到市场账号（旁路 datakeep-market/market_server/.env 的 ADMIN_*，或 DATAKEEP_MARKET_*），跳过官网同步"
    warn "稍后可: ./scripts/release.sh market $TAG"
  fi
fi

ok "完成。Release: https://github.com/${REPO}/releases/tag/${TAG}"
ok "官网下载页（同步成功后）: https://datakeep.site/"
