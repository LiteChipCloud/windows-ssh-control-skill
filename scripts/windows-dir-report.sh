#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINCTL="${SCRIPT_DIR}/winctl.sh"
WIN_USER="${WIN_USER:-Administrator}"

usage() {
  cat <<'EOF'
生成 Windows 目录分析报告（JSON）

用法:
  windows-dir-report.sh "<Windows目录路径>" [topN]

示例:
  windows-dir-report.sh "D:/workspace/sample-project" 20
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

TARGET_PATH="$1"
TOP_N="${2:-15}"

if ! [[ "$TOP_N" =~ ^[0-9]+$ ]] || [[ "$TOP_N" -lt 1 || "$TOP_N" -gt 200 ]]; then
  echo "topN 必须是 1-200 的整数" >&2
  exit 2
fi

if [[ ! -x "$WINCTL" ]]; then
  echo "缺少可执行脚本: $WINCTL" >&2
  exit 3
fi

# 单引号转义为 PowerShell 单引号字符串语法
ESCAPED_PATH="${TARGET_PATH//\'/\'\'}"
LOCAL_PS="$(mktemp "${TMPDIR:-/tmp}/win-dir-report.XXXXXX.ps1")"
REMOTE_PS="C:/Users/${WIN_USER}/AppData/Local/Temp/win-dir-report-${TOP_N}-$$.ps1"
trap 'rm -f "$LOCAL_PS"' EXIT

cat >"$LOCAL_PS" <<'PS'
param(
  [Parameter(Mandatory = $true)][string]$targetPath,
  [int]$topN = 15
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
chcp 65001 > $null

if (-not (Test-Path -LiteralPath $targetPath)) {
  [pscustomobject]@{
    generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    exists = $false
    target_path = $targetPath
    error = 'Path not found'
  } | ConvertTo-Json -Depth 4
  exit 0
}

$resolvedPath = (Resolve-Path -LiteralPath $targetPath).Path
$rootPrefix = $resolvedPath.TrimEnd('\') + '\'
$topLevel = Get-ChildItem -LiteralPath $resolvedPath -Force -ErrorAction SilentlyContinue |
  Sort-Object -Property @{Expression = { -not $_.PSIsContainer }}, Name |
  ForEach-Object {
    [pscustomobject]@{
      name = $_.Name
      type = if ($_.PSIsContainer) { 'dir' } else { 'file' }
      bytes = if ($_.PSIsContainer) { $null } else { [int64]$_.Length }
      last_write_time = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
  }

$files = Get-ChildItem -LiteralPath $resolvedPath -File -Recurse -Force -ErrorAction SilentlyContinue
$dirs = Get-ChildItem -LiteralPath $resolvedPath -Directory -Recurse -Force -ErrorAction SilentlyContinue
$totalMeasure = $files | Measure-Object -Property Length -Sum
$totalBytes = if ($null -eq $totalMeasure.Sum) { [int64]0 } else { [int64]$totalMeasure.Sum }

$extensionTop = $files |
  Group-Object -Property {
    $ext = [System.IO.Path]::GetExtension($_.Name)
    if ([string]::IsNullOrWhiteSpace($ext)) { '<no-ext>' } else { $ext.ToLowerInvariant() }
  } |
  Sort-Object Count -Descending |
  Select-Object -First $topN |
  ForEach-Object {
    [pscustomobject]@{
      extension = $_.Name
      count = [int]$_.Count
    }
  }

$subdirBucket = @{}
foreach ($f in $files) {
  if ($f.FullName.StartsWith($rootPrefix)) {
    $relative = $f.FullName.Substring($rootPrefix.Length)
  } else {
    $relative = $f.Name
  }
  $first = if ($relative.Contains('\')) { $relative.Split('\')[0] } else { '<root>' }
  if (-not $subdirBucket.ContainsKey($first)) {
    $subdirBucket[$first] = [ordered]@{ name = $first; file_count = 0; bytes = [int64]0 }
  }
  $subdirBucket[$first].file_count += 1
  $subdirBucket[$first].bytes += [int64]$f.Length
}

$subdirSizeTop = $subdirBucket.GetEnumerator() |
  ForEach-Object {
    [pscustomobject]@{
      name = $_.Value.name
      file_count = [int]$_.Value.file_count
      bytes = [int64]$_.Value.bytes
      gib = [math]::Round($_.Value.bytes / 1GB, 3)
    }
  } |
  Sort-Object bytes -Descending |
  Select-Object -First $topN

$largestFiles = $files |
  Sort-Object Length -Descending |
  Select-Object -First $topN |
  ForEach-Object {
    [pscustomobject]@{
      path = $_.FullName
      bytes = [int64]$_.Length
      gib = [math]::Round($_.Length / 1GB, 3)
      last_write_time = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
  }

$recentFiles = $files |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First $topN |
  ForEach-Object {
    [pscustomobject]@{
      path = $_.FullName
      bytes = [int64]$_.Length
      last_write_time = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
  }

[pscustomobject]@{
  generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  exists = $true
  target_path = $resolvedPath
  summary = [pscustomobject]@{
    directories = [int]$dirs.Count
    files = [int]$files.Count
    bytes = [int64]$totalBytes
    gib = [math]::Round($totalBytes / 1GB, 3)
  }
  top_level = $topLevel
  extension_top = $extensionTop
  subdir_size_top = $subdirSizeTop
  largest_files = $largestFiles
  recent_files = $recentFiles
} | ConvertTo-Json -Depth 8
PS

"$WINCTL" copy-to "$LOCAL_PS" "$REMOTE_PS"
"$WINCTL" ps "\$f='${REMOTE_PS}'; try { & \$f -targetPath '${ESCAPED_PATH}' -topN ${TOP_N} } finally { Remove-Item -LiteralPath \$f -Force -ErrorAction SilentlyContinue }"
