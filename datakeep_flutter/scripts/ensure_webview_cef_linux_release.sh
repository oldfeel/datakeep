#!/usr/bin/env bash
# webview_cef 在 Linux Debug 构建会链接 CEF Debug 库；其 DCHECK 会在中文输入法
# 离屏渲染时 FATAL 崩进程（待办等内嵌 WebView）。Windows 已默认用 Release CEF，
# 本脚本把同样逻辑补到已解析的 webview_cef/linux/CMakeLists.txt。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKER="DATAKEEP_CEF_RELEASE_IME_FIX"

PKG_CONFIG="$ROOT/.dart_tool/package_config.json"
if [[ ! -f "$PKG_CONFIG" ]]; then
  echo "[ensure_webview_cef] 未找到 package_config.json，请先 flutter pub get"
  exit 0
fi

CEF_CMAKE="$(python3 - "$PKG_CONFIG" <<'PY'
import json, sys, os
cfg = json.load(open(sys.argv[1]))
root = os.path.dirname(os.path.dirname(os.path.abspath(sys.argv[1])))
for p in cfg.get("packages", []):
    if p.get("name") != "webview_cef":
        continue
    uri = p.get("rootUri", "")
    if uri.startswith("file://"):
        path = uri[len("file://"):]
    elif uri.startswith("../") or uri.startswith("./"):
        path = os.path.normpath(os.path.join(os.path.dirname(sys.argv[1]), uri))
    else:
        path = uri
    cmake = os.path.join(path, "linux", "CMakeLists.txt")
    print(cmake if os.path.isfile(cmake) else "")
    break
else:
    print("")
PY
)"

if [[ -z "$CEF_CMAKE" || ! -f "$CEF_CMAKE" ]]; then
  echo "[ensure_webview_cef] 未找到 webview_cef/linux/CMakeLists.txt，跳过"
  exit 0
fi

if grep -q "$MARKER" "$CEF_CMAKE"; then
  echo "[ensure_webview_cef] 已打补丁: $CEF_CMAKE"
  exit 0
fi

python3 - "$CEF_CMAKE" "$MARKER" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
marker = sys.argv[2]
text = path.read_text(encoding="utf-8")
old = '''#########################################cef#########################################
set(CEF_TARGET ${PLUGIN_NAME})
ADD_LOGICAL_TARGET("libcef_lib" "${CEF_LIB_DEBUG}" "${CEF_LIB_RELEASE}")
SET_CEF_TARGET_OUT_DIR()
'''
new = f'''#########################################cef#########################################
# {marker}: Debug CEF DCHECKs crash OSR during CJK/IME (same as Windows default).
option(WEBVIEW_CEF_USE_DEBUG_CEF "Link/bundle the CEF Debug binaries for Debug builds" OFF)
set(CEF_TARGET ${{PLUGIN_NAME}})
if(WEBVIEW_CEF_USE_DEBUG_CEF)
  ADD_LOGICAL_TARGET("libcef_lib" "${{CEF_LIB_DEBUG}}" "${{CEF_LIB_RELEASE}}")
  set(_datakeep_cef_bin_dir "${{CEF_BINARY_DIR}}")
else()
  ADD_LOGICAL_TARGET("libcef_lib" "${{CEF_LIB_RELEASE}}" "${{CEF_LIB_RELEASE}}")
  set(_datakeep_cef_bin_dir "${{CEF_BINARY_DIR_RELEASE}}")
endif()
SET_CEF_TARGET_OUT_DIR()
'''
if old not in text:
    sys.stderr.write(f"[ensure_webview_cef] 未匹配到预期片段，跳过: {path}\n")
    sys.exit(0)
text = text.replace(old, new, 1)
old2 = "  list(APPEND cef_library_list ${CEF_BINARY_DIR}/${FILE})"
new2 = "  list(APPEND cef_library_list ${_datakeep_cef_bin_dir}/${FILE})"
if old2 not in text:
    sys.stderr.write(f"[ensure_webview_cef] 未匹配到 CEF_BINARY_DIR 打包行，跳过: {path}\n")
    sys.exit(0)
text = text.replace(old2, new2, 1)
path.write_text(text, encoding="utf-8")
print(f"[ensure_webview_cef] 已修补: {path}")
PY
