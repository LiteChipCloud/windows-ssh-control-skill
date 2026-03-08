# Windows SSH Control Skill

> 通过 SSH 标准化远程控制 Windows 主机（PowerShell / WSL / 文件传输 / 目录盘点）

**维护单位：芯寰云（上海）科技有限公司**

## 项目定位

`windows-ssh-control` 是一个面向 Codex/Agent 的通用技能项目，用于把跨机 Windows 控制流程固化为可复用命令。

核心目标：

1. 快速建立 Mac/Linux -> Windows 的 SSH 控制链路
2. 统一远程执行 PowerShell 与 WSL 命令
3. 标准化双向文件传输
4. 输出结构化目录盘点报告（JSON）

## 使用环境说明

### 模式 A：Windows 本机初始化模式（一次性）

适用：首次开启 Windows OpenSSH、写入公钥信任、修复 ACL。

执行端：Windows（管理员 PowerShell）

对应脚本：`scripts/setup_ssh_trust.ps1`

### 模式 B：Mac/Linux 控制 Windows（推荐）

适用：日常研发、自动化联调、跨机调试。

执行端：Mac/Linux

对应脚本：`scripts/winctl.sh`

### 模式 C：设备联调链路（扩展）

适用：Mac 本机编排 -> Windows 远程执行 -> 串口设备操作。

建议与 QuecPython Dev Skill 组合。

## 能力矩阵

| 能力 | 说明 | 命令 |
|---|---|---|
| 连通性与免密检查 | 探测主机可达、端口可达、免密可用 | `doctor` |
| 授权脚本生成 | 生成 Windows 管理员侧一键配置脚本 | `bootstrap-command` |
| 远程 PowerShell | 执行 Windows 原生命令 | `ps` |
| 远程 WSL | 执行 WSL shell 命令 | `wsl` |
| 文件上传 | 本地 -> Windows | `copy-to` |
| 文件下载 | Windows -> 本地 | `copy-from` |
| 目录盘点 | 递归统计目录规模、类型分布、大文件/最近变更 | `dir-report` |

## 快速开始

### 1. 配置目标机器参数（可选）

```bash
export WIN_USER=Administrator
export WIN_HOST=192.168.1.100
export SSH_PORT=22
```

### 2. 先做诊断

```bash
./scripts/winctl.sh doctor
```

### 3. 若未完成免密，生成并在 Windows 管理员 PowerShell 执行

```bash
./scripts/winctl.sh bootstrap-command
```

### 4. 常用操作

```bash
# PowerShell
./scripts/winctl.sh ps "hostname; whoami; Get-Date"

# WSL
./scripts/winctl.sh wsl "uname -a && whoami"

# 文件传输
./scripts/winctl.sh copy-to ./local.txt "C:/Users/Administrator/Desktop/local.txt"
./scripts/winctl.sh copy-from "C:/Users/Administrator/Desktop/report.txt" ./report.txt

# 目录报告
./scripts/winctl.sh dir-report "D:\work\project" 20
```

## 目录结构

```text
windows-ssh-control-skill/
├── SKILL.md
├── README.md
├── LICENSE
├── agents/openai.yaml
└── scripts/
    ├── winctl.sh
    ├── windows-dir-report.sh
    └── setup_ssh_trust.ps1
```

## 安全与运维建议

1. 建议使用专用 SSH 密钥，不复用个人高权限私钥
2. 为 Windows 目标机配置固定 IP 或可靠 DNS
3. 生产环境优先使用非管理员账户并做最小权限授权
4. 对 `copy-to` / 远程执行操作保留审计日志
5. 对批量命令先小范围验证再全量执行

## 与 QuecPython Skill 的组合

你可以将本项目与 `quecpython-dev-skill` 组合，实现跨机设备调试闭环：

1. 本机生成与校验代码
2. SSH 下发到 Windows
3. Windows 侧执行部署/串口测试
4. 拉回日志做判定

参考：
- [QuecPython Dev Skill](https://github.com/LiteChipCloud/quecpython-dev-skill)

## 开源许可证

本项目采用 `Apache-2.0`，详见 `LICENSE`。
