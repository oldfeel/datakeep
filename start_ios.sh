#!/bin/bash
# 仓库根入口：转发到 datakeep_flutter/start_ios.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/datakeep_flutter/start_ios.sh" "$@"
