---
name: windows-ssh-control
description: Operate a Windows machine through SSH with standardized workflows for connectivity checks, key-based bootstrap, remote PowerShell/WSL execution, directory inspection, and file transfer. Use when tasks require cross-machine Windows control from macOS/Linux or remote execution on Windows hosts.
---

# Windows SSH Control

Use this skill to execute Windows operations over SSH via `scripts/winctl.sh`.

## Core Workflow

1. Verify connectivity and key trust.
2. Execute remote commands through `ps` or `wsl`.
3. Transfer files with `copy-to` / `copy-from` when needed.
4. For directory analysis, call `dir-report` and summarize the JSON result.

## Quick Commands

Run from this skill repository root:

```bash
# 1) 连通性与免密检查
./scripts/winctl.sh doctor

# 2) 输出 Windows 侧一次性授权脚本（用户在管理员 PowerShell 执行）
./scripts/winctl.sh bootstrap-command

# 3) 执行远程 PowerShell
./scripts/winctl.sh ps "hostname; whoami; Get-Date"

# 4) 执行远程 WSL
./scripts/winctl.sh wsl "uname -a && whoami"

# 5) 文件上传/下载
./scripts/winctl.sh copy-to ./local.txt "C:/Users/Admin/Desktop/local.txt"
./scripts/winctl.sh copy-from "C:/Users/Admin/Desktop/report.txt" ./report.txt

# 6) 目录扫描报告（JSON）
./scripts/winctl.sh dir-report "D:\work\project" 20
```

## Required Behavior

Always do the following when using this skill:

1. Run `doctor` before first control attempt in a session.
2. If key auth fails, generate and provide `bootstrap-command` for the user to run on Windows admin PowerShell.
3. Use `ps` for Windows-native commands and `wsl` for Linux toolchain commands.
4. For directory inventory requests, use `dir-report` instead of ad hoc one-liners to keep output stable.
5. Preserve UTF-8 output for Chinese paths/names by relying on the built-in report script.

## Bundled Script

- `scripts/winctl.sh`: cross-machine Windows SSH control entrypoint.
- `scripts/windows-dir-report.sh`: JSON report generator for Windows directories.
- `scripts/setup_ssh_trust.ps1`: Windows-side one-time OpenSSH trust/bootstrap helper.
