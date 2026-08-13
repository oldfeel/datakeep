#!/usr/bin/env bash
# DataKeep 发版：更新版本 → 打 tag → 推送 → 触发 GitHub Actions 多平台编译
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
MODE="patch" # 默认每次 +0.0.1；可被 patch|minor|major|x.y.z 覆盖

usage() {
  cat <<'EOF'
DataKeep 发版：版本 +0.0.1 → 打 tag → 推送 → 触发 GitHub Actions 多平台编译

用法:
  ./scripts/release.sh              # 默认 +0.0.1（0.0.0 → v0.0.1 → v0.0.2 …）
  ./scripts/release.sh 1.2.0        # 设为指定版本（build+1）并发版
  ./scripts/release.sh patch        # 同默认
  ./scripts/release.sh minor        # 次版本 +1
  ./scripts/release.sh major        # 主版本 +1
  ./scripts/release.sh --dry-run    # 只打印将要做的事
  ./scripts/release.sh --no-wait    # 推送后不等待 CI
  ./scripts/release.sh --local      # 不打远程 tag，仅本机 ./scripts/build.sh

远程发版依赖公开仓 workflow「Build packages」（push tags: v*）。
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    -h|--help|help) usage ;;
    --dry-run) DRY_RUN=1 ;;
    --no-wait) NO_WAIT=1 ;;
    --local) LOCAL_ONLY=1 ;;
    patch|minor|major) MODE="$arg" ;;
    [0-9]*.[0-9]*.[0-9]*) MODE="$arg" ;;
    *)
      err "未知参数: $arg"
      usage
      ;;
  esac
done

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
    sed -i "s/^version: .*/version: ${full}/" "$PUBSPEC"
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

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "需要命令: $1"
    exit 1
  }
}
need_cmd git

git tag -a "$TAG" -m "Release $TAG"
ok "已创建 tag $TAG"

log "推送分支与 tag…"
git push origin HEAD
git push origin "$TAG"
ok "已推送 $TAG → 将触发 GitHub Actions「Build packages」"

REPO="$(git remote get-url origin | sed -E 's#.*github.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')"
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
log "下载全部产物到 ./dist-release/ …"
mkdir -p "$ROOT/dist-release"
gh run download "$RUN_ID" --repo "$REPO" -D "$ROOT/dist-release"
ls -lhR "$ROOT/dist-release" || true
ok "完成。也可在 Release 页下载: https://github.com/${REPO}/releases/tag/${TAG}"
