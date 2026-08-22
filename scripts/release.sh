#!/usr/bin/env bash
# DataKeep 发版：更新版本 → 打 tag → 推送 → 触发 GitHub Actions 多平台编译
# 编完后可选：通知官网从 GitHub Release 拉取并写入 GitHub 下载链 + 生成 BT 种子
#
# 用法:
#   ./scripts/release.sh              # 默认 patch +0.0.1（从 0.0.0 → v0.0.1 → v0.0.2 …）
#   ./scripts/release.sh 1.2.0        # 设为指定版本（build+1）并发版
#   ./scripts/release.sh patch        # 同默认：修订号 +1
#   ./scripts/release.sh minor        # 次版本 +1（0.0.x → 0.1.0）
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
#   DATAKEEP_USE_PROXY=1 ./scripts/release.sh download v0.0.4  # 走本机代理（默认 127.0.0.1:7897）
#
# 官网同步（编完后默认尝试）:
#   优先读环境变量 DATAKEEP_MARKET_TOKEN / USER / PASSWORD
#   否则自动读旁路仓库 ../datakeep-market/market_server/.env 的 ADMIN_USERNAME/PASSWORD
#   DATAKEEP_MARKET_URL 默认 https://admin.datakeep.site
#   DATAKEEP_MARKET_ENV  可指定 .env 路径
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
MODE="patch" # 默认每次 +0.0.1；可被 patch|minor|major|x.y.z 覆盖
ACTION="release" # release | market | links | torrents | download
RELEASE_TAG=""
USE_PROXY=0

MARKET_URL="${DATAKEEP_MARKET_URL:-https://admin.datakeep.site}"
MARKET_URL="${MARKET_URL%/}"
PUBLIC_SITE="${DATAKEEP_PUBLIC_SITE:-https://datakeep.site}"
PUBLIC_SITE="${PUBLIC_SITE%/}"

usage() {
  cat <<'EOF'
DataKeep 发版：版本 +0.0.1 → 打 tag → 推送 → 触发 GitHub Actions 多平台编译
编完后默认调用官网接口：服务器从 GitHub Release 拉包、写入 GitHub 链并生成 BT 种子与磁力链。

用法:
  ./scripts/release.sh              # 默认 +0.0.1（0.0.0 → v0.0.1 → v0.0.2 …）
  ./scripts/release.sh 1.2.0        # 设为指定版本（build+1）并发版
  ./scripts/release.sh patch        # 同默认
  ./scripts/release.sh minor        # 次版本 +1
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

官网同步：默认用旁路 datakeep-market/market_server/.env 的 ADMIN_*；
也可设 DATAKEEP_MARKET_TOKEN，或 DATAKEEP_MARKET_USER + DATAKEEP_MARKET_PASSWORD。
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
  log "通知官网从 GitHub Release 同步到市场服务器（$MARKET_URL）…"
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
    warn "dry-run：将下载四端包到 $packages，.torrent 到 $torrents"
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

  if command -v gh >/dev/null 2>&1; then
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

  log "从官网拉取 .torrent → $torrents"
  local p tmissing=""
  for p in android linux macos windows; do
    if ! curl -fsS "${PUBLIC_SITE}/api/client/${p}/torrent" -o "$torrents/${p}.torrent"; then
      tmissing="${tmissing} ${p}"
      warn "未拿到 $p 的 .torrent（请先 ./scripts/release.sh market $tag）"
    fi
  done

  log "写入 $magnets"
  if command -v jq >/dev/null 2>&1; then
    local resp
    resp="$(curl -fsS "${PUBLIC_SITE}/api/client/releases")" || resp=""
    if [[ -n "$resp" ]] && [[ "$(echo "$resp" | jq -r '.code')" == "0" ]]; then
      {
        echo "# DataKeep ${tag} magnets — $(date -Iseconds)"
        for p in android linux macos windows; do
          echo "$p$(echo "$resp" | jq -r --arg p "$p" '.data[] | select(.platform==$p) | "\t" + (.magnetUrl // "")')"
        done
      } >"$magnets"
    else
      warn "无法从官网 API 写入 magnets.txt"
    fi
  else
    warn "未安装 jq，跳过 magnets.txt"
  fi

  ok "已下载到 $out"
  ls -lh "$packages"
  if [[ -z "$tmissing" ]]; then
    ls -lh "$torrents"
  fi
  [[ -f "$magnets" ]] && ok "磁力链: $magnets"
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

  log "从官网 API 读取磁力链（$PUBLIC_SITE）…"
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
        warn "官网 $p 版本为 v$api_ver，与指定 v$ver 不一致"
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

bump_semver() {
  local kind="$1" # patch|minor|major
  local major minor patch
  IFS=. read -r major minor patch <<<"$VER_NAME"
  case "$kind" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
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
  err "本地已存在 tag $TAG，请先 bump 版本或删除旧 tag"
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
      echo "  将: 官网 sync-github → $MARKET_URL （tag $TAG）"
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

log "等待 workflow 出现…"
RUN_ID=""
for _ in $(seq 1 30); do
  RUN_ID="$(gh run list --repo "$REPO" --workflow=build.yml --branch "$TAG" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  if [[ -n "$RUN_ID" && "$RUN_ID" != "null" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  warn "暂未查到 run，请稍后: gh run list --workflow=build.yml"
  exit 0
fi

ok "Run #$RUN_ID — 跟踪中（CEF/多平台可能较久）…"
gh run watch "$RUN_ID" --repo "$REPO" --exit-status || {
  err "构建失败，查看: gh run view $RUN_ID --repo $REPO --log-failed"
  exit 1
}

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
