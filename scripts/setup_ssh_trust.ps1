param(
  [Parameter(Mandatory = $true)]
  [string]$PublicKey,
  [switch]$RestartSshd
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).
  IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  throw '请使用“管理员: Windows PowerShell”运行本脚本。当前会话不是管理员权限。'
}

function Ensure-OpenSshServer {
  $svc = Get-Service sshd -ErrorAction SilentlyContinue
  if (-not $svc) {
    Write-Host 'OpenSSH Server 未安装，开始安装...'
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
  }

  Set-Service sshd -StartupType Automatic
  if ((Get-Service sshd).Status -ne 'Running') {
    Start-Service sshd
  }

  if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
      -Name 'OpenSSH-Server-In-TCP' `
      -DisplayName 'OpenSSH Server (TCP-In)' `
      -Direction Inbound `
      -Action Allow `
      -Protocol TCP `
      -LocalPort 22 | Out-Null
  }
}

function Ensure-PubkeyAuthenticationEnabled {
  $sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
  if (-not (Test-Path $sshdConfig)) {
    return
  }

  $lines = Get-Content -Path $sshdConfig -ErrorAction SilentlyContinue
  if (-not $lines) {
    $lines = @()
  }

  $updated = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*#?\s*PubkeyAuthentication\s+') {
      $lines[$i] = 'PubkeyAuthentication yes'
      $updated = $true
    }
  }

  if (-not $updated) {
    $lines += 'PubkeyAuthentication yes'
  }

  Set-Content -Path $sshdConfig -Value $lines -Encoding Ascii
}

function Ensure-KeyInFile {
  param(
    [Parameter(Mandatory = $true)] [string]$FilePath,
    [Parameter(Mandatory = $true)] [string]$KeyLine
  )

  $dir = Split-Path -Parent $FilePath
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  if (-not (Test-Path $FilePath)) {
    New-Item -ItemType File -Force -Path $FilePath | Out-Null
  }
  
  # 规范化为 ASCII，避免 UTF-16 导致 OpenSSH 无法解析 authorized_keys
  $existing = @()
  if (Test-Path $FilePath) {
    $existing = Get-Content -Path $FilePath -ErrorAction SilentlyContinue
  }
  $normalized = @($existing + $KeyLine) | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -Unique
  Set-Content -Path $FilePath -Value $normalized -Encoding Ascii
}

Ensure-OpenSshServer
Ensure-PubkeyAuthenticationEnabled

$sshDir = Join-Path $env:USERPROFILE '.ssh'
$userAuth = Join-Path $sshDir 'authorized_keys'
$adminAuth = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'

$userSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
$systemSid = '*S-1-5-18'
$adminSid = '*S-1-5-32-544'

Ensure-KeyInFile -FilePath $userAuth -KeyLine $PublicKey
Ensure-KeyInFile -FilePath $adminAuth -KeyLine $PublicKey

icacls $sshDir /inheritance:r | Out-Null
icacls $sshDir /grant:r "*${userSid}:(OI)(CI)F" "${systemSid}:(OI)(CI)F" | Out-Null

icacls $userAuth /inheritance:r | Out-Null
icacls $userAuth /grant:r "*${userSid}:F" "${systemSid}:F" | Out-Null
icacls $userAuth /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' | Out-Null

icacls $adminAuth /inheritance:r | Out-Null
icacls $adminAuth /grant:r "${adminSid}:F" "${systemSid}:F" | Out-Null
icacls $adminAuth /remove:g '*S-1-1-0' '*S-1-5-11' '*S-1-5-32-545' "*${userSid}" | Out-Null

if ($RestartSshd) {
  Restart-Service sshd
}

Write-Host 'SSH trust 配置完成。'
