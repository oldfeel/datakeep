# DataKeep Windows 打包（对齐 GitHub Actions build.yml）
# 用法:
#   powershell -ExecutionPolicy Bypass -File scripts/windows_build.ps1
# 产物: dist/datakeep-<version>-windows-x64.zip
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root 'datakeep_flutter'
$Dist = Join-Path $Root 'dist'

if (-not (Test-Path (Join-Path $App 'pubspec.yaml'))) {
  throw "未找到 $App\pubspec.yaml"
}

function Require-Cmd([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "未找到 $Name，请先加入 PATH"
  }
}

Require-Cmd flutter
Set-Location $App
Write-Host "==> 工作目录: $App"

# --- Syncthing（始终走 build 脚本；脚本内用 stamp 决定是否重编，避免沿用旧的 CUI 控制台版）---
$SyncthingExe = Join-Path $App 'bin\syncthing.exe'
function Get-PeSubsystem([string]$Path) {
  if (-not (Test-Path $Path)) { return 0 }
  $fs = [IO.File]::OpenRead($Path)
  try {
    $br = New-Object IO.BinaryReader($fs)
    $fs.Seek(0x3C, 'Begin') | Out-Null
    $pe = $br.ReadInt32()
    $fs.Seek($pe + 0x5C, 'Begin') | Out-Null
    return [int]$br.ReadUInt16()
  } finally { $fs.Close() }
}
$bash = @(
  "${env:ProgramFiles}\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
  if (-not (Test-Path $SyncthingExe)) {
    throw @"
缺少 bin\syncthing.exe，且未找到 Git bash。
请先在 Git bash 中执行:
  cd datakeep_flutter && bash scripts/build_desktop_syncthing.sh
"@
  }
  Write-Host '==> 无 Git bash，沿用已有 bin\syncthing.exe'
} else {
  Write-Host '==> 编译/校验 syncthing.exe（windowsgui）...'
  $env:SYNCTHING_GOOS = 'windows'
  $env:SYNCTHING_GOARCH = 'amd64'
  & $bash 'scripts/build_desktop_syncthing.sh'
  if ($LASTEXITCODE -ne 0) { throw 'syncthing 编译失败' }
}
if (-not (Test-Path $SyncthingExe)) { throw '未生成 bin\syncthing.exe' }
$sub = Get-PeSubsystem $SyncthingExe
# IMAGE_SUBSYSTEM_WINDOWS_GUI = 2；若仍是控制台(3) 则删掉强制重编一次
if ($sub -ne 2) {
  Write-Host "==> syncthing.exe 子系统=$sub（需要 GUI=2），强制重编..."
  if (-not $bash) { throw "syncthing.exe 为控制台子系统($sub)，请安装 Git bash 后重跑" }
  Remove-Item -Force $SyncthingExe
  $stamp = Join-Path $App 'bin\.syncthing-build.stamp'
  if (Test-Path $stamp) { Remove-Item -Force $stamp }
  $env:SYNCTHING_GOOS = 'windows'
  $env:SYNCTHING_GOARCH = 'amd64'
  & $bash 'scripts/build_desktop_syncthing.sh'
  if ($LASTEXITCODE -ne 0) { throw 'syncthing 强制重编失败' }
  $sub = Get-PeSubsystem $SyncthingExe
  if ($sub -ne 2) { throw "syncthing.exe 仍非 GUI 子系统 (subsystem=$sub)" }
}
Write-Host "==> syncthing.exe OK (subsystem=$sub GUI)"

Write-Host '==> flutter config / pub get'
flutter config --enable-windows-desktop
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# share_plus 头文件补丁（与 CI 相同）
$headers = @()
if ($env:PUB_CACHE) {
  $headers += Get-ChildItem -Path $env:PUB_CACHE -Recurse -Filter share_plus_windows_plugin.h -ErrorAction SilentlyContinue
}
$headers += Get-ChildItem -Path "$env:LOCALAPPDATA\Pub\Cache" -Recurse -Filter share_plus_windows_plugin.h -ErrorAction SilentlyContinue
foreach ($h in ($headers | Select-Object -ExpandProperty FullName -Unique)) {
  $text = Get-Content -Raw -Path $h
  $fixed = $text -replace 'static std::wstring SharePlusWindowsPlugin::Utf16FromUtf8', 'static std::wstring Utf16FromUtf8'
  if ($fixed -ne $text) {
    Set-Content -Path $h -Value $fixed -NoNewline
    Write-Host "patched $h"
  }
}

Write-Host '==> flutter build windows --release'
flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$line = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches.Groups[1].Value
$version = ($line -split '\+')[0]
$release = Get-ChildItem -Path 'build\windows' -Recurse -Directory |
  Where-Object { $_.FullName -match '\\runner\\Release$' } |
  Select-Object -First 1
if (-not $release) { throw 'Release directory not found' }

$bundled = Join-Path $release.FullName 'data\bin\syncthing.exe'
if (-not (Test-Path $bundled)) {
  if (-not (Test-Path $SyncthingExe)) { throw 'syncthing.exe not found for bundling' }
  New-Item -ItemType Directory -Force -Path (Split-Path $bundled) | Out-Null
  Copy-Item -Force $SyncthingExe $bundled
  Write-Host "Copied syncthing.exe -> $bundled"
}
if (-not (Test-Path $bundled)) { throw 'Release missing data\bin\syncthing.exe' }

# 部分本机（旧工具链）上 Release libcef 无法 LoadLibrary(193)，进程秒退。
# GitHub windows-latest 的 Release CEF 正常；本机脚本检测到失败后改捆绑 Debug CEF。
function Test-LibCefLoads([string]$Dir) {
  $py = @'
import ctypes, os, sys
os.chdir(sys.argv[1])
k = ctypes.WinDLL("kernel32", use_last_error=True)
LoadLibraryW = k.LoadLibraryW
LoadLibraryW.argtypes = [ctypes.c_wchar_p]
LoadLibraryW.restype = ctypes.c_void_p
k.LoadLibraryW("chrome_elf.dll")
h = k.LoadLibraryW("libcef.dll")
sys.exit(0 if h else 1)
'@
  $tmp = Join-Path $env:TEMP 'datakeep_test_libcef.py'
  Set-Content -Path $tmp -Value $py -Encoding UTF8
  & python $tmp $Dir
  return ($LASTEXITCODE -eq 0)
}

function Get-CefDebugDir {
  $cfg = Join-Path $App '.dart_tool\package_config.json'
  if (-not (Test-Path $cfg)) { return $null }
  $root = python -c @"
import json, os
from pathlib import Path
from urllib.parse import urlparse
cfg = Path(r'$($cfg.Replace('\','/'))')
data = json.loads(cfg.read_text(encoding='utf-8'))
root = ''
for p in data['packages']:
    if p.get('name') != 'webview_cef':
        continue
    u = p.get('rootUri', '')
    root = urlparse(u).path if u.startswith('file:') else str((cfg.parent / u).resolve())
    break
if root.startswith('/') and len(root) > 2 and root[2] == ':':
    root = root[1:]
print(os.path.join(root, 'third', 'cef', 'Debug') if root else '')
"@
  if ($root -and (Test-Path (Join-Path $root 'libcef.dll'))) { return $root }
  return $null
}

if (-not (Test-LibCefLoads $release.FullName)) {
  Write-Host '==> 本机 Release libcef 无法加载，尝试改用可用的 Release CEF（GitHub 包 / 环境变量）'
  $cefReleaseCandidates = @()
  if ($env:DATAKEEP_CEF_RELEASE_DIR) { $cefReleaseCandidates += $env:DATAKEEP_CEF_RELEASE_DIR }
  $cefReleaseCandidates += @(
    (Join-Path $env:USERPROFILE 'Downloads\datakeep-0.2.3-windows-x64\datakeep-0.2.3-windows'),
    (Join-Path $env:USERPROFILE 'Downloads\datakeep-0.2.2-windows-x64\datakeep-0.2.2-windows'),
    (Join-Path $env:USERPROFILE 'Downloads\datakeep-0.2.1-windows-x64\datakeep-0.2.1-windows')
  )
  $cefFiles = @(
    'chrome_elf.dll', 'd3dcompiler_47.dll', 'dxcompiler.dll', 'dxil.dll',
    'libcef.dll', 'libEGL.dll', 'libGLESv2.dll', 'v8_context_snapshot.bin',
    'vk_swiftshader.dll', 'vk_swiftshader_icd.json', 'vulkan-1.dll'
  )
  $copiedRelease = $false
  foreach ($cand in $cefReleaseCandidates) {
    if (-not $cand) { continue }
    $probe = Join-Path $cand 'libcef.dll'
    if (-not (Test-Path $probe)) { continue }
    if ((Get-Item $probe).Length -gt 350000000) {
      # 约 400MB 多为 Debug CEF，跳过
      continue
    }
    Write-Host "==> 使用 Release CEF 目录: $cand"
    foreach ($f in $cefFiles) {
      $src = Join-Path $cand $f
      if (Test-Path $src) {
        Copy-Item -Force $src (Join-Path $release.FullName $f)
      }
    }
    if (Test-LibCefLoads $release.FullName) {
      Write-Host '==> Release CEF（外源）加载正常'
      $copiedRelease = $true
      break
    }
  }
  if (-not $copiedRelease) {
    Write-Host '==> 改用 Debug CEF（可能启动时闪控制台；仅本机打包）'
    $cefDebug = Get-CefDebugDir
    if (-not $cefDebug) { throw 'Release libcef 不可用，且未找到 webview_cef/third/cef/Debug' }
    foreach ($f in $cefFiles) {
      $src = Join-Path $cefDebug $f
      if (Test-Path $src) {
        Copy-Item -Force $src (Join-Path $release.FullName $f)
        Write-Host "  CEF Debug -> $f"
      }
    }
    if (-not (Test-LibCefLoads $release.FullName)) {
      throw '替换 Debug CEF 后 libcef 仍无法加载'
    }
    Write-Host '==> Debug CEF 加载正常'
  }
} else {
  Write-Host '==> Release libcef 加载正常'
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$name = "datakeep-$version-windows"
$stage = Join-Path $env:TEMP $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -Path (Join-Path $release.FullName '*') -Destination $stage -Recurse -Force
$zip = Join-Path $Dist "$name-x64.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $stage -DestinationPath $zip -Force

# 同步解压目录，避免一直双击旧的 dist\...\datakeep-*-windows
$outDir = Join-Path $Dist $name
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item -Path (Join-Path $stage '*') -Destination $outDir -Recurse -Force
Remove-Item -Recurse -Force $stage

Get-Item $zip | Format-List FullName, Length
Write-Host "OK: $zip"
Write-Host "已同步解压目录: $outDir"
Write-Host "请运行: $outDir\datakeep_flutter.exe"
Write-Host "对外发版请仍用 GitHub / scripts/release.sh（正式 Release CEF）"
