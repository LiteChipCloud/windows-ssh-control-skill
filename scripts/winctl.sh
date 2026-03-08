#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_KEY_PATH="${HOME}/.ssh/windows_ssh_control_ed25519"

WIN_USER="${WIN_USER:-Administrator}"
WIN_HOST="${WIN_HOST:-192.168.1.100}"
SSH_PORT="${SSH_PORT:-22}"
KEY_PATH="${KEY_PATH:-$DEFAULT_KEY_PATH}"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}"

TARGET="${WIN_USER}@${WIN_HOST}"

usage() {
  cat <<'EOF'
Windows 控制脚本（Mac -> Windows）

用法:
  winctl.sh doctor
  winctl.sh bootstrap-command
  winctl.sh print-pubkey
  winctl.sh shell
  winctl.sh shell-password
  winctl.sh ps "<PowerShell 命令>"
  winctl.sh wsl "<WSL bash 命令>"
  winctl.sh copy-to <本地文件> <Windows目标路径>
  winctl.sh copy-from <Windows源路径> <本地目标路径>
  winctl.sh dir-report "<Windows目录路径>" [topN]

环境变量(可选):
  WIN_USER, WIN_HOST, SSH_PORT, KEY_PATH, KNOWN_HOSTS_FILE
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1" >&2
    exit 1
  fi
}

ensure_keypair() {
  need_cmd ssh-keygen
  mkdir -p "$(dirname "$KEY_PATH")"
  if [[ ! -f "$KEY_PATH" || ! -f "${KEY_PATH}.pub" ]]; then
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "mac-to-windows-control"
  fi
}

ssh_with_key() {
  ensure_keypair
  ssh \
    -p "$SSH_PORT" \
    -i "$KEY_PATH" \
    -o ConnectTimeout=5 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
    "$TARGET" "$@"
}

scp_with_key() {
  ensure_keypair
  scp \
    -P "$SSH_PORT" \
    -i "$KEY_PATH" \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
    "$@"
}

encode_powershell() {
  need_cmd iconv
  need_cmd base64
  printf '%s' "$1" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\r\n'
}

print_bootstrap_command() {
  ensure_keypair
  local pub_key
  pub_key="$(cat "${KEY_PATH}.pub")"

  cat <<EOF
# 在 Windows PowerShell(管理员)执行以下脚本，一次性完成 SSH 免密授权
\$ErrorActionPreference = 'Stop'
\$isAdmin = ([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).
  IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not \$isAdmin) {
  throw '请使用“管理员: Windows PowerShell”运行该脚本。'
}
\$pubKey = @'
$pub_key
'@

if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
  Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
}

Set-Service sshd -StartupType Automatic
if ((Get-Service sshd).Status -ne 'Running') {
  Start-Service sshd
}

if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (TCP-In)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 | Out-Null
}

\$sshdConfig = Join-Path \$env:ProgramData 'ssh\\sshd_config'
if (Test-Path \$sshdConfig) {
  \$cfg = Get-Content -Path \$sshdConfig -ErrorAction SilentlyContinue
  if (-not \$cfg) { \$cfg = @() }
  \$updated = \$false
  for (\$i = 0; \$i -lt \$cfg.Count; \$i++) {
    if (\$cfg[\$i] -match '^\\s*#?\\s*PubkeyAuthentication\\s+') {
      \$cfg[\$i] = 'PubkeyAuthentication yes'
      \$updated = \$true
    }
  }
  if (-not \$updated) {
    \$cfg += 'PubkeyAuthentication yes'
  }
  Set-Content -Path \$sshdConfig -Value \$cfg -Encoding Ascii
}

\$sshDir = Join-Path \$env:USERPROFILE '.ssh'
\$userAuth = Join-Path \$sshDir 'authorized_keys'
\$adminAuth = Join-Path \$env:ProgramData 'ssh\\administrators_authorized_keys'
\$userSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
\$systemSid = '*S-1-5-18'
\$adminSid = '*S-1-5-32-544'

New-Item -ItemType Directory -Force -Path \$sshDir | Out-Null
if (-not (Test-Path \$userAuth)) { New-Item -ItemType File -Force -Path \$userAuth | Out-Null }
if (-not (Test-Path \$adminAuth)) { New-Item -ItemType File -Force -Path \$adminAuth | Out-Null }

\$userLines = @()
if (Test-Path \$userAuth) { \$userLines = Get-Content -Path \$userAuth -ErrorAction SilentlyContinue }
\$userNormalized = @(\$userLines + \$pubKey) | Where-Object { \$_ -and \$_.Trim().Length -gt 0 } | Select-Object -Unique
Set-Content -Path \$userAuth -Value \$userNormalized -Encoding Ascii

\$adminLines = @()
if (Test-Path \$adminAuth) { \$adminLines = Get-Content -Path \$adminAuth -ErrorAction SilentlyContinue }
\$adminNormalized = @(\$adminLines + \$pubKey) | Where-Object { \$_ -and \$_.Trim().Length -gt 0 } | Select-Object -Unique
Set-Content -Path \$adminAuth -Value \$adminNormalized -Encoding Ascii

icacls \$sshDir /inheritance:r | Out-Null
icacls \$sshDir /grant:r "*\${userSid}:(OI)(CI)F" "\${systemSid}:(OI)(CI)F" | Out-Null
icacls \$userAuth /inheritance:r | Out-Null
icacls \$userAuth /grant:r "*\${userSid}:F" "\${systemSid}:F" | Out-Null
icacls \$userAuth /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' | Out-Null
icacls \$adminAuth /inheritance:r | Out-Null
icacls \$adminAuth /grant:r "\${adminSid}:F" "\${systemSid}:F" | Out-Null
icacls \$adminAuth /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' "*\${userSid}" | Out-Null

Restart-Service sshd
Write-Host 'SSH trust configured. You can now use key-based login from Mac.'
EOF
}

doctor() {
  need_cmd ping
  need_cmd nc
  ensure_keypair

  echo "TARGET: $TARGET"
  echo "SSH_PORT: $SSH_PORT"
  echo "KEY_PATH: $KEY_PATH"
  echo

  echo "[1/3] ping 探测..."
  if ping -c 2 "$WIN_HOST" >/dev/null 2>&1; then
    echo "  OK: $WIN_HOST 可达"
  else
    echo "  FAIL: $WIN_HOST 不可达"
    exit 2
  fi

  echo "[2/3] 端口探测..."
  if nc -z -G 2 "$WIN_HOST" "$SSH_PORT" >/dev/null 2>&1; then
    echo "  OK: $WIN_HOST:$SSH_PORT 已开放"
  else
    echo "  FAIL: $WIN_HOST:$SSH_PORT 未开放"
    exit 3
  fi

  echo "[3/3] 免密登录检测..."
  if ssh \
    -p "$SSH_PORT" \
    -i "$KEY_PATH" \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
    "$TARGET" "whoami" >/dev/null 2>&1; then
    echo "  OK: SSH 免密可用"
    return 0
  fi

  echo "  WARN: 免密还未完成。请先执行:"
  echo "        ./scripts/winctl.sh bootstrap-command"
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi
shift || true

case "$cmd" in
  doctor)
    doctor
    ;;
  bootstrap-command)
    print_bootstrap_command
    ;;
  print-pubkey)
    ensure_keypair
    cat "${KEY_PATH}.pub"
    ;;
  shell)
    ssh_with_key
    ;;
  shell-password)
    ssh -p "$SSH_PORT" "$TARGET"
    ;;
  ps)
    if [[ $# -lt 1 ]]; then
      echo "缺少参数: PowerShell 命令" >&2
      exit 1
    fi
    ps_cmd="$1"
    if [[ $# -gt 1 ]]; then
      ps_cmd="$*"
    fi
    ps_payload="$(encode_powershell "\$ProgressPreference='SilentlyContinue'; $ps_cmd")"
    ssh_with_key "powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $ps_payload"
    ;;
  wsl)
    if [[ $# -lt 1 ]]; then
      echo "缺少参数: WSL bash 命令" >&2
      exit 1
    fi
    wsl_cmd="$*"
    wsl_cmd="${wsl_cmd//\'/\'\"\'\"\'}"
    ps_cmd="\$ProgressPreference='SilentlyContinue'; wsl.exe sh -lc '$wsl_cmd'"
    ps_payload="$(encode_powershell "$ps_cmd")"
    ssh_with_key "powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $ps_payload"
    ;;
  copy-to)
    if [[ $# -ne 2 ]]; then
      echo "用法: winctl.sh copy-to <本地文件> <Windows目标路径>" >&2
      exit 1
    fi
    scp_with_key "$1" "${TARGET}:$2"
    ;;
  copy-from)
    if [[ $# -ne 2 ]]; then
      echo "用法: winctl.sh copy-from <Windows源路径> <本地目标路径>" >&2
      exit 1
    fi
    scp_with_key "${TARGET}:$1" "$2"
    ;;
  dir-report)
    if [[ $# -lt 1 || $# -gt 2 ]]; then
      echo "用法: winctl.sh dir-report <Windows目录路径> [topN]" >&2
      exit 1
    fi
    "${SCRIPT_DIR}/windows-dir-report.sh" "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
