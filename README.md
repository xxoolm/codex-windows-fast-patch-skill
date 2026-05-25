# Codex Windows Fast Patch Skill

语言：中文 | [English](README.en.md)

这是 `codex-windows-fast-patch` skill 的公开脱敏版本，用于在 Windows 上快速恢复 Codex Desktop 升级后失效的本地补丁和能力开关。

## 主要功能

- 在 Codex Desktop 升级后重新应用 Windows MSIX 补丁。
- 验证 Fast Mode 请求是否真的带上 `service_tier=priority`。
- 注册和修复本地插件市场配置。
- 修复本地插件市场清单目录结构。
- 刷新 Windows Computer Use 兼容文件。
- 解除 Computer Control 页面里 `Any App` / `任意应用` 被组织或地区门控禁用的问题。

## 平台支持

当前只支持 Windows。

这个 skill 依赖 Windows Store / MSIX 包结构、PowerShell、`Get-AppxPackage`、`makeappx.exe`、`signtool.exe`、Windows 用户环境变量，以及 Windows Computer Use helper 路径。

不要在 macOS 上直接运行。macOS 需要单独的实现流程，例如处理 Codex `.app` 包、ASAR 解包和重打包、`codesign` 或 quarantine、shell 脚本，以及 macOS 自己的 Computer Use 可用性门控。

## 文件说明

- `SKILL.md`：Codex skill 主说明。
- `agents/openai.yaml`：agent 配置。
- `scripts/repatch-codex-windows.ps1`：一键重新应用补丁的包装脚本。
- `scripts/patch_codex_fast_mode_windows_msix.ps1`：MSIX / ASAR 补丁脚本。
- `scripts/install-computer-use-local.ps1`：Windows Computer Use 本地兼容文件安装和校验脚本。

## 安装

先克隆仓库，然后在仓库根目录打开 PowerShell，只复制 skill 需要的文件：

```powershell
$source = (Get-Location).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {
  throw '请在 codex-windows-fast-patch-skill 仓库根目录运行此命令。'
}

$dest = Join-Path $env:USERPROFILE '.codex\skills\codex-windows-fast-patch'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Copy-Item -Force -LiteralPath (Join-Path $source 'SKILL.md') -Destination $dest
Copy-Item -Recurse -Force -LiteralPath (Join-Path $source 'agents') -Destination $dest
Copy-Item -Recurse -Force -LiteralPath (Join-Path $source 'scripts') -Destination $dest
```

安装或更新后，重启 Codex，让它重新加载 skill 元数据。

## 使用

安装后，在 Codex 中直接要求重新应用 Windows Fast Patch，或使用 skill 中的包装脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-fast-patch\scripts\repatch-codex-windows.ps1" -DryRun
```

确认 dry run 找到补丁目标后，再执行正式补丁：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-fast-patch\scripts\repatch-codex-windows.ps1"
```

## 致谢

感谢 [LinuxDo community](https://linux.do/) 中相关讨论和反馈对这个工作流的启发。

## 脱敏说明

此仓库不会包含本地 Codex 状态、认证文件、日志、插件缓存、生成的字节码、依赖目录或机器专属配置。

发布前已检查常见敏感信息模式，例如 API key、GitHub token、认证文件、私有配置和本机路径等。
